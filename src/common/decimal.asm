; Decimal numbers for the console programs. The program defines numbuf, 8 bytes.

; HL as a decimal number without blanks, to DE.
emit_number:
        push    de
        ld      bc,numbuf
        call    format5
        pop     de
        ld      hl,numbuf
        ld      b,5
emit_number_next:
        ld      a,(hl)
        inc     hl
        cp      ' '
        jr      z,emit_number_skip
        ld      (de),a
        inc     de
emit_number_skip:
        djnz    emit_number_next
        ret

; HL as a decimal number in five columns, with blanks in front, to DE.
emit_decimal5:
        push    de
        ld      bc,numbuf
        call    format5
        pop     de
        ld      hl,numbuf
        ld      bc,5
        ldir
        ret

; HL = a number, BC = a buffer of five bytes: the number there with blanks in front.
format5:
        ld      d,1
        push    bc
        pop     ix
        ld      bc,10000
        call    digit
        ld      bc,1000
        call    digit
        ld      bc,100
        call    digit
        ld      bc,10
        call    digit
        ld      a,l
        add     a,'0'
        ld      (ix+0),a
        ret
; One digit: how many times BC goes into HL. D is 1 while the digits so far are zeros.
digit:
        ld      a,'0'-1
digit_count:
        inc     a
        or      a
        sbc     hl,bc
        jr      nc,digit_count
        add     hl,bc
        cp      '0'
        jr      nz,digit_put
        bit     0,d
        jr      z,digit_put
        ld      a,' '
        jr      digit_store
digit_put:
        ld      d,0
digit_store:
        ld      (ix+0),a
        inc     ix
        ret
