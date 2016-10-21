; The output of the program through the BDOS (functions 2, 6 and 9) does not go to the
; screen, which is the screen of the debugger: it goes to the last three lines of text
; that the output window shows. The hook runs on the stack of the program.

OUT_LINES:      equ     3

bdos_hook:
        ld      a,c
        cp      2
        jr      z,hook_char
        cp      6
        jr      z,hook_direct
        cp      9
        jr      z,hook_string
        cp      26
        jr      z,hook_dma
bdos_next:
        jp      0                       ; The BDOS entry, put here when the program is loaded
hook_dma:
        ld      (nsd_dma),de            ; the program's DMA address, put back before it runs
        jr      bdos_next
hook_char:
        ld      a,e
        jr      out_char
hook_direct:
        ld      a,e
        cp      0FEh
        jr      nc,bdos_next            ; FFh reads a key
        jr      out_char
hook_string:
        ex      de,hl
hook_string_next:
        ld      a,(hl)
        cp      '$'
        ret     z
        inc     hl
        push    hl
        call    out_char
        pop     hl
        jr      hook_string_next

; Add the character A to the output window. Destroys everything.
out_char:
        cp      0Dh
        jr      z,out_cr
        cp      0Ah
        jr      z,out_newline
        cp      9
        jr      z,out_tab
        cp      20h
        ret     c
        cp      7Fh
        ret     nc
        ld      c,a
        ld      a,(out_col)
        cp      80
        jr      c,out_store
        push    bc
        call    out_newline
        pop     bc
        xor     a
out_store:
        ld      e,a
        ld      d,0
        ld      hl,nsd_out+(OUT_LINES-1)*80
        add     hl,de
        ld      (hl),c
        inc     a
        ld      (out_col),a
        ret
out_tab:
        ld      a,(out_col)
        and     7
        ld      b,a
        ld      a,8
        sub     b
        ld      b,a
out_tab_next:
        push    bc
        ld      a,' '
        call    out_char
        pop     bc
        djnz    out_tab_next
        ret
out_cr:
        xor     a
        ld      (out_col),a
        ret
out_newline:
        ld      hl,nsd_out+80
        ld      de,nsd_out
        ld      bc,(OUT_LINES-1)*80
        ldir
        ld      hl,nsd_out+(OUT_LINES-1)*80
        ld      (hl),' '
        ld      de,nsd_out+(OUT_LINES-1)*80+1
        ld      bc,79
        ldir
        xor     a
        ld      (out_col),a
        ret

out_clear:
        ld      hl,nsd_out
        ld      (hl),' '
        ld      de,nsd_out+1
        ld      bc,OUT_LINES*80-1
        ldir
        xor     a
        ld      (out_col),a
        ret
