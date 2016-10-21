; NorthStar Advantage direct-video backend.
;
; This program uses the 64K Graphics CP/M map: page 2 is in 4000h-7FFFh.
; That page is temporarily replaced by video RAM while a glyph is written.
; Keep all code and the stack below 4000h; text and shadow data are accessed
; only while the normal CP/M mapping is restored.
;
; The backend tracks the output position itself and does not send cursor
; movement codes to the ROM driver: each BIOS console call costs several
; milliseconds. The ROM cursor is hidden before a cell changes and shown once,
; at the tracked position, when the editor waits for a key.

stack_top:      equ     03F00h
; Advantage 64K Graphics CP/M TPA allocation. The document may use the
; 4000h-7FFFh video window: the renderer reads only the glyph table and the
; shadow screen while video RAM is mapped. The yank buffer runs from B000h
; to the BDOS, over the CCP, so VI exits with a warm boot.
text:           equ     04000h
TEXT_SIZE:      equ     07000h          ; 28 KiB, to AFFFh
; The undo log follows the document and the yank buffer follows the log, up to
; the BDOS. Only the shadow screen has to stay below 4000h.
undo_buffer:    equ     0B000h
UNDO_SIZE:      equ     4096
yank_buffer:    equ     undo_buffer+UNDO_SIZE
ADV_MIN_YANK:   equ     0400h
; Low memory, from the top: the stack, the '.' key buffers and the shadow
; screen. The program image (code, glyph table and variables) grows up to the
; shadow screen, so make check measures the image against that label.
CMD_KEYS_MAX:   equ     128
cmd_keys:       equ     stack_top-0100h-2*CMD_KEYS_MAX
dot_keys:       equ     cmd_keys+CMD_KEYS_MAX
screen_shadow:  equ     cmd_keys-80*24

        include "adv_screen.asm"

platform_init:
        call    adv_find_vdb
        jr      nc,adv_vdb_found
        ld      de,adv_no_vdb_msg
        ld      c,9
        call    BDOS
        jp      quit
adv_vdb_found:
        call    adv_set_yank_limit
        ld      hl,screen_shadow
        ld      (hl),0FFh
        ld      de,screen_shadow+1
        ld      bc,80*24-1
        ldir
        xor     a
        ld      (adv_x),a
        ld      (adv_y),a
        ld      a,1             ; The CP/M prompt left the ROM cursor visible.
        ld      (adv_cursor_shown),a
        call    adv_read_scan
        ld      (adv_last_scan),a
        ret

; The yank buffer ends at the page of the BDOS entry in 0006h.
adv_set_yank_limit:
        ld      hl,(0006h)
        ld      l,0
        ld      de,yank_buffer
        or      a
        sbc     hl,de
        jr      c,adv_tpa_too_small
        ld      (yank_limit),hl
        ld      de,ADV_MIN_YANK
        or      a
        sbc     hl,de
        ret     nc
adv_tpa_too_small:
        ld      de,adv_small_tpa_msg
        ld      c,9
        call    BDOS
        jp      quit

; The keypad sends cursor codes with Cursor Lock on (the emulator's PC arrow
; keys send the same codes). Raw F0h-F7h (Shift with some function keys) are
; dropped so they cannot act as the internal cursor-key codes.
platform_map_key:
        ld      hl,adv_key_map
        ld      b,(adv_key_map_end-adv_key_map)/2
adv_map_scan:
        cp      (hl)
        inc     hl
        jr      z,adv_map_found
        inc     hl
        djnz    adv_map_scan
        cp      KEY_UP
        ret     c
        cp      KEY_PAGE_UP+1
        ret     nc
        xor     a
        ret
adv_map_found:
        ld      a,(hl)
        ret

adv_key_map:
        defb    082h,KEY_UP             ; Keypad 8
        defb    08Ah,KEY_DOWN           ; Keypad 2
        defb    088h,KEY_LEFT           ; Keypad 4
        defb    086h,KEY_RIGHT          ; Keypad 6
        defb    087h,KEY_HOME           ; Keypad 7
        defb    084h,KEY_END            ; Keypad 1
        defb    083h,KEY_PAGE_DOWN      ; Keypad 3
        defb    089h,KEY_PAGE_UP        ; Keypad 9
adv_key_map_end:

; The shared renderer streams a complete frame. Track its terminal coordinates
; and update only cells whose character differs from the shadow screen.
platform_output_char:
        cp      020h
        jr      nc,adv_output_printable
        cp      01Eh
        jr      z,adv_output_home
        cp      00Dh
        jr      z,adv_output_cr
        cp      00Ah
        jr      z,adv_output_lf
        cp      01Fh
        jr      z,adv_output_newline
        cp      00Ch
        jr      z,adv_output_right
        cp      00Eh
        jp      z,adv_clear_eol
        cp      008h
        jr      z,adv_output_backspace
        jp      adv_output_control

; The position stops after column 80 instead of wrapping: a full-width row
; is followed by a new line from the core, which would leave a blank row.
adv_output_printable:
        cp      07Fh
        ret     nc
        call    adv_draw_cell
        ld      a,(adv_x)
        cp      80
        ret     nc
        inc     a
        ld      (adv_x),a
        ret

adv_output_home:
        xor     a
        ld      (adv_x),a
        ld      (adv_y),a
        jp      adv_read_scan
adv_output_cr:
        xor     a
        ld      (adv_x),a
        ret
adv_output_newline:
        xor     a
        ld      (adv_x),a
adv_output_lf:
        ld      a,(adv_y)
        inc     a
        ld      (adv_y),a
        ret
adv_output_backspace:
        ld      a,(adv_x)
        or      a
        ret     z
        dec     a
        ld      (adv_x),a
        ret
adv_output_right:
        ld      a,(adv_x)
        inc     a
        ld      (adv_x),a
        ret

; Pass any other control code to the ROM driver.
adv_output_control:
        ld      e,a
        ld      c,6
        jp      BDOS

; Bold text is drawn with each glyph row ORed with itself shifted one pixel
; right (bit 7 is the leftmost pixel). The shadow marks bold cells with bit 7.
platform_show_cursor:
        jp      adv_show_cursor

platform_bold_on:
        ld      a,80h
        ld      (adv_style),a
        ret

platform_bold_off:
        xor     a
        ld      (adv_style),a
        ret

; Clear from the tracked cursor to column 79. Rows whose shadow tail is
; already blank need no video access, which is the common case on a redraw.
adv_clear_eol:
        ld      a,(adv_y)
        cp      24
        ret     nc
        ld      a,(adv_x)
        cp      80
        ret     nc
        call    adv_shadow_address
        ld      a,(adv_x)
        ld      b,a
        ld      a,80
        sub     b
        ld      b,a
adv_clear_check:
        ld      a,(hl)
        cp      ' '
        jr      nz,adv_clear_needed
        inc     hl
        djnz    adv_clear_check
        ret
adv_clear_needed:
        call    adv_hide_cursor
        call    adv_shadow_address
        ; Keep the old shadow bytes until the physical clear has been done.
        ; Repainting every trailing space on each insert redraw caused the
        ; entire text area to flash even when no visible character changed.
        call    adv_row_scan
        ld      (adv_clear_scan),a

        ld      a,i
        push    af
        di
        ld      a,(adv_x)
        cp      64
        jr      nc,adv_clear_right_only

        ld      a,ADV_VRAM_LEFT
        out     (ADV_MMU_BANK1),a
        ld      a,(adv_x)
        add     a,040h
        ld      d,a
        ld      a,64
        ld      c,a
        ld      a,(adv_x)
        ld      b,a
        ld      a,c
        sub     b
        ld      c,a
        call    adv_clear_columns

        ld      a,ADV_VRAM_RIGHT
        out     (ADV_MMU_BANK1),a
        ld      d,040h
        ld      c,16
        call    adv_clear_columns
        jr      adv_clear_restore

adv_clear_right_only:
        ld      a,ADV_VRAM_RIGHT
        out     (ADV_MMU_BANK1),a
        ld      a,(adv_x)
        sub     64
        add     a,040h
        ld      d,a
        ld      a,80
        ld      c,a
        ld      a,(adv_x)
        ld      b,a
        ld      a,c
        sub     b
        ld      c,a
        call    adv_clear_columns

adv_clear_restore:
        ld      a,ADV_RAM_PAGE1
        out     (ADV_MMU_BANK1),a
        pop     af
        jp      po,adv_clear_irq_was_off
        ei
adv_clear_irq_was_off:
        ret

; D is the mapped video column and C is the number of columns to clear.
adv_clear_columns:
        ld      a,c
        or      a
        ret     z
adv_clear_column_loop:
        ld      a,(hl)
        cp      ' '
        jr      z,adv_clear_column_done
        ld      (hl),' '
        ld      a,(adv_clear_scan)
        ld      e,a
        ld      b,10
        xor     a
adv_clear_scan_loop:
        ld      (de),a
        inc     e
        djnz    adv_clear_scan_loop
adv_clear_column_done:
        inc     hl
        inc     d
        dec     c
        jr      nz,adv_clear_column_loop
        ret

; Scroll the display by A text rows (signed, 1 to 22 in size): positive moves
; the content up, as when the view moves down the document. The hardware
; display start moves by 10 scanlines a row, the ROM data block follows it,
; and the shadow screen moves with the picture. Rows that come into view are
; marked stale, so the next frame draws only them and the changed cells.
platform_scroll:
        ld      (adv_scroll_rows),a
        call    adv_hide_cursor
        ld      a,(adv_scroll_rows)
        ld      b,a
        add     a,a
        add     a,a
        add     a,a
        add     a,b
        add     a,b             ; rows * 10, modulo 256
        ld      b,a
        ld      a,(adv_scan)
        add     a,b
        call    adv_set_scan
        ld      a,(adv_scroll_rows)
        bit     7,a
        jr      nz,adv_scroll_down
        call    adv_rows_to_bytes       ; HL = rows * 80
        push    hl
        ld      de,screen_shadow
        add     hl,de                   ; Source: the first row that stays
        push    hl
        ld      hl,80*24
        pop     de
        pop     bc
        push    bc
        or      a
        sbc     hl,bc                   ; Bytes that stay
        ld      b,h
        ld      c,l
        ex      de,hl
        ld      de,screen_shadow
        call    copy_forward
        ex      de,hl                   ; HL = first stale byte
        pop     bc
        ld      de,-80                  ; The status row moved up into the text
        add     hl,de                   ; and is stale as well.
        ld      de,80
        ex      de,hl
        add     hl,bc
        ld      b,h
        ld      c,l
        ex      de,hl
        jr      adv_mark_stale
adv_scroll_down:
        neg
        call    adv_rows_to_bytes       ; HL = rows * 80
        push    hl
        ex      de,hl
        ld      hl,80*24
        or      a
        sbc     hl,de                   ; Bytes that stay
        ld      b,h
        ld      c,l
        ld      de,screen_shadow-1
        add     hl,de                   ; Source: last byte that stays
        ld      de,screen_shadow+80*24-1
        call    copy_backward
        ld      hl,screen_shadow
        pop     bc
; Fill BC (at least 1) shadow bytes from HL with FFh, a value no cell has.
adv_mark_stale:
        ld      (hl),0FFh
        dec     bc
        ld      a,b
        or      c
        ret     z
        ld      d,h
        ld      e,l
        inc     de
        ldir
        ret

; HL = A * 80.
adv_rows_to_bytes:
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl                   ; * 16
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,hl                   ; * 64
        add     hl,de                   ; * 80
        ret

; Set the display start scanline in the hardware, the ROM data block and
; the renderer, so that the next frame does not treat it as a new origin.
adv_set_scan:
        ld      (adv_scan),a
        ld      (adv_last_scan),a
        ld      hl,(adv_vdb)
        ld      de,ADV_VDB_SCAN
        add     hl,de
        ld      (hl),a
        out     (ADV_VIDEO_START),a
        ret

; Start at the ROM's current display origin. If it moved since the last
; frame, every shadow cell is stale.
platform_begin_redraw:
        ld      a,1
        ld      (adv_frame_drawn),a
        call    adv_output_home
        ld      a,(adv_scan)
        ld      b,a
        ld      a,(adv_last_scan)
        cp      b
        ret     z
        ld      a,b
        ld      (adv_last_scan),a
        ld      hl,screen_shadow
        ld      (hl),0FFh
        ld      de,screen_shadow+1
        ld      bc,80*24-1
        ldir
        ret

platform_end_redraw:
        ret

; Draw the B characters at HL as one row of the screen, clear what follows
; them and start the next row. Each character is compared with the shadow
; screen first, and only a cell that differs is drawn.
platform_draw_row:
        ld      a,b
        ld      (adv_row_len),a
        ex      de,hl
        xor     a
        ld      (adv_x),a
        ld      a,(adv_y)
        cp      24
        jr      nc,adv_row_end
        ld      a,(adv_row_len)
        or      a
        jr      z,adv_row_end
        push    de
        call    adv_hide_cursor
        call    adv_row_scan
        ld      (adv_row_e),a
        call    adv_shadow_address
        pop     de
        ld      a,(adv_row_len)
        cp      65
        jr      c,adv_row_left
        sub     64
        ld      (adv_row_right),a
        ld      b,64
        ld      a,ADV_VRAM_LEFT
        call    adv_row_segment
        ld      a,(adv_row_right)
        ld      b,a
        ld      a,ADV_VRAM_RIGHT
        call    adv_row_segment
        jr      adv_row_end
adv_row_left:
        ld      b,a
        ld      a,ADV_VRAM_LEFT
        call    adv_row_segment
adv_row_end:
        ld      a,(adv_row_len)
        ld      (adv_x),a
        call    adv_clear_eol
        jp      adv_output_newline

; Compare B characters at DE with the shadow cells at HL and draw those that
; differ, in the columns of one video bank (A) that start with the first. The
; bank is mapped once for the whole run, with interrupts off. The text buffer
; is out of reach while it is mapped, and nothing here uses it.
adv_row_segment:
        ld      (adv_bank),a
        ld      c,0
        ld      a,i
        push    af
        di
        ld      a,(adv_bank)
        out     (ADV_MMU_BANK1),a
adv_seg_loop:
        ld      a,(de)
        cp      (hl)
        jr      nz,adv_seg_draw
adv_seg_next:
        inc     de
        inc     hl
        inc     c
        djnz    adv_seg_loop
        ld      a,ADV_RAM_PAGE1
        out     (ADV_MMU_BANK1),a
        pop     af
        ret     po
        ei
        ret
; A = the character, HL its shadow cell, C its column in the bank. The glyph
; has 9 scanlines after a blank first one, in the 10 of the cell.
adv_seg_draw:
        cp      07Fh
        jr      nc,adv_seg_next
        ld      (hl),a
        ex      af,af'
        ld      a,c
        add     a,040h
        exx
        ld      d,a
        ex      af,af'
        sub     020h
        ld      l,a
        ld      h,0
        ld      c,l
        ld      b,h
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,bc
        ld      bc,adv_font_table
        add     hl,bc
        ld      a,(adv_row_e)
        ld      e,a
        xor     a
        ld      (de),a
        ld      a,e
        cp      247
        jr      nc,adv_seg_wrap
        inc     e
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        exx
        jr      adv_seg_next
adv_seg_wrap:
        inc     e
        ld      b,9
adv_seg_wrap_row:
        ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     e
        djnz    adv_seg_wrap_row
        exx
        jr      adv_seg_next

; Leave the current row as it is and start the next one. Carry is set when the
; row cannot be left: its cells on the screen are not known (they were moved in
; by a scroll, or the shadow screen was cleared), so it has to be drawn.
platform_skip_row:
        ld      a,(adv_y)
        cp      24
        jr      nc,adv_skip_ok
        xor     a
        ld      (adv_x),a
        call    adv_shadow_address
        ld      a,(hl)
        inc     a
        jr      z,adv_skip_no
adv_skip_ok:
        call    adv_output_newline
        or      a
        ret
adv_skip_no:
        scf
        ret


; Leave the ROM cursor at the start of the status row, so the CP/M prompt
; follows VI's last frame. Before the first frame (a refused file), the ROM
; cursor is still where the CP/M output left it.
platform_exit:
        ld      a,(adv_frame_drawn)
        or      a
        ret     z
        ld      a,1
        call    platform_status_column
        jp      platform_show_cursor

; The core keeps live registers across these calls; putc preserves them.
platform_newline:
        ld      a,01Fh
        jp      putc

platform_position_cursor:
        ld      a,(ansi_row)
        dec     a
        ld      (adv_y),a
        ld      a,(ansi_col)
        dec     a
        ld      (adv_x),a
        ret

platform_clear_screen:
        ret

platform_clear_eol:
        ld      a,00Eh
        jp      putc

platform_status_start:
        xor     a
        ld      (adv_x),a
        ld      a,23
        ld      (adv_y),a
        ld      a,00Eh
        jp      putc

; A = one-based column on the status row.
platform_status_column:
        dec     a
        ld      (adv_x),a
        ld      a,23
        ld      (adv_y),a
        ret

platform_search_prompt:
        call    platform_status_start
        ld      a,'/'
        jp      putc

adv_last_scan:  defb 0
adv_row_len:    defb 0
adv_row_right:  defb 0
adv_row_e:      defb 0
adv_clear_scan: defb 0
adv_scroll_rows: defb 0
adv_frame_drawn: defb 0
adv_no_vdb_msg: defb 'VI: Graphics CP/M video block not found',0Dh,0Ah,'$'
adv_small_tpa_msg: defb 'VI: needs the 64K Graphics CP/M memory map',0Dh,0Ah,'$'

