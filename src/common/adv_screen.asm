; Screen primitives of the NorthStar Advantage, shared by the programs that draw text
; on its bitmap screen directly (vi and nsadb).
;
; The program defines BDOS and screen_shadow (80*24 bytes) before it includes this
; file, and keeps its code, stack, shadow screen and the font out of 4000h-7FFFh:
; video RAM replaces that page while a glyph is written.
;
; A cell whose shadow value has bit 7 set is in the style of adv_style: bold, or
; inverse video when adv_inverse is not zero.

ADV_MMU_BANK1:  equ     0A1h
ADV_RAM_PAGE1:  equ     02h
ADV_VRAM_LEFT:  equ     080h
ADV_VRAM_RIGHT: equ     081h
ADV_VDB_X:      equ     0               ; ROM video data block: cursor column
ADV_VDB_Y:      equ     1               ; Cursor scanline
ADV_VDB_SCAN:   equ     4               ; Display start scanline
ADV_VIDEO_START: equ    090h            ; Display start scanline register
ADV_CURSOR_ON:  equ     018h
ADV_CURSOR_OFF: equ     019h

; The BIOS passes its video data block to the ROM driver with LD IX,nn. Find
; that instruction so the renderer uses the block the ROM actually uses.
; Page zero (0080h-00FFh) holds the CP/M command tail and DMA buffer, not it.
; Carry when there is no such instruction.
adv_find_vdb:
        ld      hl,(0001h)      ; BIOS warm-boot entry
        ld      l,0
adv_find_vdb_loop:
        ld      a,(hl)
        inc     hl
        cp      0DDh
        jr      nz,adv_find_vdb_next
        ld      a,(hl)
        cp      021h
        jr      z,adv_found_vdb
adv_find_vdb_next:
        ld      a,h
        or      l
        jr      nz,adv_find_vdb_loop
        scf
        ret
adv_found_vdb:
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (adv_vdb),de
        or      a
        ret

adv_read_scan:
        ld      hl,(adv_vdb)
        ld      de,ADV_VDB_SCAN
        add     hl,de
        ld      a,(hl)
        ld      (adv_scan),a
        ret

; A = physical starting scanline of text row adv_y, modulo 256.
adv_row_scan:
        ld      a,(adv_y)
        ld      b,a
        add     a,a
        add     a,a
        add     a,a             ; row * 8
        ld      c,a
        ld      a,b
        add     a,a             ; row * 2
        add     a,c             ; row * 10
        ld      c,a
        ld      a,(adv_scan)
        add     a,c
        ret

adv_hide_cursor:
        ld      a,(adv_cursor_shown)
        or      a
        ret     z
        xor     a
        ld      (adv_cursor_shown),a
        ld      e,ADV_CURSOR_OFF
        ld      c,6
        jp      BDOS

; Show the ROM cursor at the tracked cell. The cursor is hidden while its data
; block position changes, so the ROM never XORs it at a stale address.
adv_show_cursor:
        ld      hl,(adv_vdb)
        ld      a,h
        or      l
        ret     z
        ld      a,(adv_y)
        cp      24
        jr      c,adv_show_row_ok
        ld      a,23
        ld      (adv_y),a
adv_show_row_ok:
        ld      a,(adv_x)
        cp      80
        jr      c,adv_show_col_ok
        ld      a,79
        ld      (adv_x),a
adv_show_col_ok:
        call    adv_row_scan
        ld      (adv_cursor_scan),a
        ld      a,(adv_cursor_shown)
        or      a
        jr      z,adv_show_place
        ld      hl,(adv_vdb)
        ld      a,(adv_x)
        cp      (hl)            ; ADV_VDB_X
        jr      nz,adv_show_move
        inc     hl              ; ADV_VDB_Y
        ld      a,(adv_cursor_scan)
        cp      (hl)
        ret     z
adv_show_move:
        call    adv_hide_cursor
adv_show_place:
        ld      hl,(adv_vdb)
        ld      a,(adv_x)
        ld      (hl),a          ; ADV_VDB_X
        inc     hl
        ld      a,(adv_cursor_scan)
        ld      (hl),a          ; ADV_VDB_Y
        ld      a,1
        ld      (adv_cursor_shown),a
        ld      e,ADV_CURSOR_ON
        ld      c,6
        jp      BDOS

; Draw A at the tracked cell unless the shadow screen already has it, in the
; same weight.
adv_draw_cell:
        ld      (adv_char),a
        ld      a,(adv_x)
        cp      80
        ret     nc
        ld      a,(adv_y)
        cp      24
        ret     nc
        call    adv_shadow_address
        ld      a,(adv_style)
        ld      b,a
        ld      a,(adv_char)
        or      b
        cp      (hl)
        ret     z
        ld      (adv_cell),a
        call    adv_hide_cursor
        call    adv_draw_glyph
        ld      hl,(adv_shadow_ptr)
        ld      a,(adv_cell)
        ld      (hl),a
        ret

; HL = screen_shadow + adv_y*80 + adv_x, from a row table: this runs once
; for every character the frame draws.
adv_shadow_address:
        ld      a,(adv_y)
        add     a,a
        ld      l,a
        ld      h,0
        ld      de,adv_shadow_rows
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      a,(adv_x)
        ld      l,a
        ld      h,0
        add     hl,de
        ld      (adv_shadow_ptr),hl
        ret

adv_shadow_rows:
        defw    screen_shadow+0*80,screen_shadow+1*80,screen_shadow+2*80
        defw    screen_shadow+3*80,screen_shadow+4*80,screen_shadow+5*80
        defw    screen_shadow+6*80,screen_shadow+7*80,screen_shadow+8*80
        defw    screen_shadow+9*80,screen_shadow+10*80,screen_shadow+11*80
        defw    screen_shadow+12*80,screen_shadow+13*80,screen_shadow+14*80
        defw    screen_shadow+15*80,screen_shadow+16*80,screen_shadow+17*80
        defw    screen_shadow+18*80,screen_shadow+19*80,screen_shadow+20*80
        defw    screen_shadow+21*80,screen_shadow+22*80,screen_shadow+23*80

; Glyphs are pre-expanded to ten scanlines. The source and this routine reside
; below 4000h, so both remain available during the temporary bank switch.
adv_draw_glyph:
        call    adv_row_scan
        ld      e,a             ; physical starting scanline, modulo 256
        ld      a,(adv_char)
        sub     020h
        ld      c,a
        ld      b,0
        ld      h,b
        ld      l,c
        add     hl,hl           ; character index * 2
        add     hl,hl           ; * 4
        add     hl,hl           ; * 8
        add     hl,bc           ; * 9
        ld      bc,adv_font_table
        add     hl,bc
        xor     a
        ld      (adv_blank),a
        ld      a,(adv_style)
        or      a
        jr      z,adv_glyph_source_ready
        push    de
        ld      de,adv_glyph_buf
        ld      b,9
        ld      a,(adv_inverse)
        or      a
        jr      nz,adv_inverse_start
adv_style_row:
        ld      a,(hl)
        ld      c,a
        srl     a
        or      c
        ld      (de),a
        inc     hl
        inc     de
        djnz    adv_style_row
adv_glyph_style_done:
        pop     de
        ld      hl,adv_glyph_buf
        jr      adv_glyph_source_ready
adv_inverse_start:
        ld      a,0FFh
        ld      (adv_blank),a
adv_inverse_row:
        ld      a,(hl)
        cpl
        ld      (de),a
        inc     hl
        inc     de
        djnz    adv_inverse_row
        jr      adv_glyph_style_done
adv_glyph_source_ready:

        ld      a,(adv_x)
        cp      64
        jr      nc,adv_glyph_right_bank
        add     a,040h
        ld      d,a
        ld      a,ADV_VRAM_LEFT
        jr      adv_glyph_bank_ready
adv_glyph_right_bank:
        sub     64
        add     a,040h
        ld      d,a
        ld      a,ADV_VRAM_RIGHT
adv_glyph_bank_ready:
        ld      (adv_bank),a

        ; Save and restore interrupt state. The MMU register is write-only;
        ; Graphics CP/M keeps main RAM page 2 in bank 1.
        ld      a,i
        push    af
        di
        ld      a,(adv_bank)
        out     (ADV_MMU_BANK1),a
        ld      a,(adv_blank)
        ld      (de),a          ; scanline 0 of the cell: blank, or lit when inverse
        ld      a,e
        cp      247
        jr      nc,adv_glyph_wrap
        inc     e
        ld      bc,9
        ldir
        jr      adv_glyph_restore
adv_glyph_wrap:
        inc     e               ; wrap the scanline without changing the column
        ld      b,9
adv_glyph_wrap_loop:
        ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     e               ; wrap scanline without changing column
        djnz    adv_glyph_wrap_loop
adv_glyph_restore:
        ld      a,ADV_RAM_PAGE1
        out     (ADV_MMU_BANK1),a
        pop     af
        jp      po,adv_glyph_irq_was_off
        ei
adv_glyph_irq_was_off:
        ret

adv_x:          defb 0
adv_y:          defb 0
adv_scan:       defb 0
adv_char:       defb 0
adv_bank:       defb 0
adv_cursor_scan: defb 0
adv_cursor_shown: defb 0
adv_style:      defb 0
adv_inverse:    defb 0
adv_blank:      defb 0
adv_cell:       defb 0
adv_glyph_buf:  defs 9,0
adv_shadow_ptr: defw 0
adv_vdb:        defw 0

adv_font_table:
        include "adv_font.asm"
