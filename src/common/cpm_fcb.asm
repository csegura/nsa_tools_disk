; CP/M command line helpers shared by the programs. The program defines TAIL
; (0080h) and `args` (a word: the text after the program name) for make_tail.

; The new command tail for the program: a space and the arguments at (args).
make_tail:
        ld      hl,(args)
        ld      b,0
count_args:
        ld      a,(hl)
        or      a
        jr      z,args_counted
        inc     hl
        inc     b
        ld      a,b
        cp      125
        jr      nz,count_args
args_counted:
        ld      a,b
        or      a
        jr      z,tail_empty
        inc     a
        ld      (TAIL),a
        ld      hl,TAIL+1
        ld      (hl),' '
        inc     hl
        ex      de,hl
        ld      hl,(args)
        ld      c,b
        ld      b,0
        ldir
        ret
tail_empty:
        xor     a
        ld      (TAIL),a
        ret

skip_blanks:
        ld      a,(hl)
        cp      ' '
        ret     nz
        inc     hl
        jr      skip_blanks

; Fill the FCB at DE from the text at HL as the CCP does: the drive, the name
; and the extension in capitals and padded with blanks, '*' made into '?', and
; the four bytes after them zero. The second FCB of a program overlaps the
; command tail from the byte after those, so no more is written. Returns HL
; after the name.
parse_fcb:
        push    de
        xor     a
        ld      (de),a
        inc     de
        ld      b,11
        ld      a,' '
fcb_blank:
        ld      (de),a
        inc     de
        djnz    fcb_blank
        ld      b,4
        xor     a
fcb_zero:
        ld      (de),a
        inc     de
        djnz    fcb_zero
        pop     de
        call    skip_blanks
        ld      a,(hl)
        cp      'A'
        jr      c,fcb_fields
        cp      'P'+1
        jr      nc,fcb_fields
        ld      c,a
        inc     hl
        ld      a,(hl)
        cp      ':'
        jr      z,fcb_drive
        dec     hl
        jr      fcb_fields
fcb_drive:
        inc     hl
        ld      a,c
        sub     'A'-1
        ld      (de),a
fcb_fields:
        push    de
        inc     de
        ld      b,8
        call    parse_field
        ld      a,(hl)
        cp      '.'
        jr      nz,fcb_done
        inc     hl
        pop     de
        push    de
        ld      a,e
        add     a,9
        ld      e,a
        jr      nc,fcb_extension
        inc     d
fcb_extension:
        ld      b,3
        call    parse_field
fcb_done:
        pop     de
        ret

; Copy up to B characters of a name from HL to DE; stop at a delimiter.
parse_field:
        ld      a,(hl)
        call    is_delimiter
        ret     z
        inc     hl
        cp      '*'
        jr      z,field_star
        cp      'a'
        jr      c,field_store
        cp      'z'+1
        jr      nc,field_store
        sub     20h
field_store:
        ld      c,a
        ld      a,b
        or      a
        jr      z,parse_field
        ld      a,c
        ld      (de),a
        inc     de
        dec     b
        jr      parse_field
field_star:
        ld      a,b
        or      a
        jr      z,parse_field
        ld      a,'?'
field_fill:
        ld      (de),a
        inc     de
        djnz    field_fill
        jr      parse_field

; Z when A ends a name: the end of the text, a blank or a control, or one of
; = _ . : ; < >
is_delimiter:
        or      a
        ret     z
        cp      ' '+1
        jr      c,delimiter_yes
        cp      '='
        ret     z
        cp      '_'
        ret     z
        cp      '.'
        ret     z
        cp      ':'
        ret     z
        cp      ';'
        ret     z
        cp      '<'
        ret     z
        cp      '>'
        ret
delimiter_yes:
        cp      a
        ret
