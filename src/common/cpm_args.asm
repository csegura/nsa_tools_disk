; The words of the command line, for the small tools. The program defines TAIL (0080h),
; `work` (130 bytes), `word` (64 bytes) and `args_pos` (a word), and `tool_option`, which
; takes the letter of an option in A (carry when it is not one it knows).
;
; CP/M makes the whole command line capital letters before the program sees it.

; Copy the command tail and start at its first word.
args_init:
        ld      a,(TAIL)
        and     07Fh
        ld      c,a
        ld      b,0
        ld      hl,TAIL+1
        ld      de,work
        or      a
        jr      z,args_copied
        ldir
args_copied:
        xor     a
        ld      (de),a
        ld      hl,work
        ld      (args_pos),hl
        ret

; The next word of the command line goes to `word`, ended by a zero; a word between "
; quotes may have blanks. Carry when there is none.
next_word:
        ld      hl,(args_pos)
        call    skip_blanks
        ld      a,(hl)
        or      a
        jr      nz,word_start
        ld      (args_pos),hl
        scf
        ret
word_start:
        ld      de,word
        ld      b,63
        ld      c,' '
        cp      '"'
        jr      nz,word_copy
        ld      c,'"'
        inc     hl
word_copy:
        ld      a,(hl)
        or      a
        jr      z,word_end
        cp      c
        jr      z,word_close
        inc     hl
        ld      (de),a
        inc     de
        dec     b
        jr      nz,word_copy
        jr      word_end
word_close:
        ld      a,c
        cp      '"'
        jr      nz,word_end
        inc     hl
word_end:
        xor     a
        ld      (de),a
        ld      (args_pos),hl
        or      a
        ret

; The word is -abc: each letter goes to tool_option. Carry for an option that is not known.
parse_options:
        ld      hl,word+1
option_next:
        ld      a,(hl)
        or      a
        ret     z
        inc     hl
        push    hl
        call    tool_option
        pop     hl
        ret     c
        jr      option_next

; A decimal number at HL: DE has it and HL is after it; carry when there is none or it is
; more than 65535.
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
        jr      c,decimal_overflow
        add     hl,hl
        jr      c,decimal_overflow
        add     hl,de
        jr      c,decimal_overflow
        add     hl,hl
        jr      c,decimal_overflow
        ld      e,a
        ld      d,0
        add     hl,de
        jr      c,decimal_overflow
        ex      de,hl
        pop     hl
        inc     hl
        inc     b
        jr      decimal_next
decimal_overflow:
        pop     hl
        scf
        ret
decimal_end:
        ld      a,b
        or      a
        ret     nz
        scf
        ret
