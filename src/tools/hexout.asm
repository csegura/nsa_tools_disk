; HEXOUT: write a file to the console as lines of Intel HEX (32 bytes in each), so that a remote
; operator can read it through RCON (docs/rcon.md) and so that HEXIN can write it on another disk.
;
;     HEXOUT [d:]file
;
; A line is ":LLAAAA00" and the data, then the checksum (the two's complement of the sum of all the
; bytes before it), and the last line is ":00000001FF". The file is read in records of 128 bytes, as
; CP/M keeps it, so what comes is a multiple of 128 bytes (a text file has Ctrl-Z fill in the last
; record). A file of more than 64 KB is cut at 64 KB.

BDOS:           equ     0005h
FCB:            equ     005Ch
LINE_BYTES:     equ     32

        org     0100h
start:  ld      (orig_sp),sp
        ld      sp,stack_top
        call    main
        ld      sp,(orig_sp)
        ret

main:   ld      a,(FCB+1)
        cp      ' '
        jr      z,usage
        ld      hl,FCB+1
        ld      b,11
main_wild:
        ld      a,(hl)
        cp      '?'
        jr      z,usage
        inc     hl
        djnz    main_wild
        ld      de,FCB
        ld      c,15                    ; open
        call    BDOS
        inc     a
        jr      nz,main_open
        ld      de,msg_not_found
        jp      print
main_open:
        xor     a
        ld      (FCB+32),a              ; the first record
        ld      de,sector
        ld      c,26                    ; set the DMA address
        call    BDOS
        ld      hl,0
        ld      (address),hl
main_read:
        ld      de,FCB
        ld      c,20                    ; read the next record
        call    BDOS
        or      a
        jr      nz,main_end
        call    send_record
        jr      nc,main_read
        ld      de,FCB                  ; 64 KB are written: is there more?
        ld      c,20
        call    BDOS
        or      a
        jr      nz,main_end
        ld      de,msg_cut
        call    print
main_end:
        ld      de,msg_eof
        jp      print
usage:  ld      de,msg_usage
        jp      print

; The 128 bytes of `sector` as four lines. Carry when the address would go over 65535.
send_record:
        ld      hl,sector
        ld      b,128/LINE_BYTES
send_line:
        push    bc
        call    send_one
        pop     bc
        ret     c
        djnz    send_line
        or      a
        ret

; The line of the data at HL (and the address): HL moves on, carry at the end of the 64 KB.
send_one:
        ld      de,line
        ld      a,':'
        ld      (de),a
        inc     de
        ld      c,0                     ; the sum
        ld      a,LINE_BYTES
        call    put_byte
        ld      a,(address+1)
        call    put_byte
        ld      a,(address)
        call    put_byte
        xor     a
        call    put_byte
        ld      b,LINE_BYTES
send_data:
        ld      a,(hl)
        inc     hl
        call    put_byte
        djnz    send_data
        xor     a
        sub     c
        call    put_byte
        ld      a,13
        ld      (de),a
        inc     de
        ld      a,10
        ld      (de),a
        inc     de
        ld      a,'$'
        ld      (de),a
        push    hl
        ld      de,line
        call    print
        ld      hl,(address)
        ld      de,LINE_BYTES
        add     hl,de
        ld      (address),hl
        pop     hl
        ret

; A as two hexadecimal digits at DE, and into the sum in C.
put_byte:
        push    af
        add     a,c
        ld      c,a
        pop     af
        push    af
        rrca
        rrca
        rrca
        rrca
        call    put_digit
        pop     af
put_digit:
        and     0Fh
        add     a,'0'
        cp      '9'+1
        jr      c,put_digit_store
        add     a,'A'-'9'-1
put_digit_store:
        ld      (de),a
        inc     de
        ret

print:  ld      c,9
        jp      BDOS

msg_usage:      defm    "Usage: HEXOUT [d:]file",13,10,'$'
msg_not_found:  defm    "HEXOUT: file not found",13,10,'$'
msg_cut:        defm    "HEXOUT: the file is more than 64 KB: only the first 64 KB were written",13,10,'$'
msg_eof:        defm    ":00000001FF",13,10,'$'

orig_sp:        defw    0
address:        defw    0
line:           defs    2+2+4+2+LINE_BYTES*2+2+3
sector:         defs    128
                defs    64
stack_top:
