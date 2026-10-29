; The options of the serial line that TERM and RCON share: -b RATE, -d 5|6|7|8, -p N|E|O and -s 1|2.
; The program defines baud_index (0 to 4: 1200 to 19200), line_data, line_parity and line_stops (the
; letters of the option), baud_code, `word`, `next_word`, `parse_decimal` and sio_setup
; (adv_sio.asm). `line_option` takes the letter of an option in A: carry when it is not one of them.

line_option:
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
