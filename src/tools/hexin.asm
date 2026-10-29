; HEXIN: make a file from lines of Intel HEX that come on the console (what HEXOUT writes). With RCON
; the console is the serial line, so a remote operator can send a file to the disk of the NSA.
;
;     HEXIN [d:]file
;
; The file must not exist. HEXIN answers "HEXIN: ready" when it reads the console; the operator
; must wait for it. The lines come without echo. Each line is answered with "." when it is
; good (a line that was already stored is good too, so the operator may send it again when the answer
; was lost) and with "!" when the checksum, the address or the format is wrong: send it again. The
; record ":00000001FF" ends the file, the last record of 128 bytes is filled with Ctrl-Z, and the
; answer is "OK" and the number of bytes. Ctrl-C or ESC stops and erases the file.

BDOS:           equ     0005h
FCB:            equ     005Ch
CTRL_C:         equ     03h
ESC:            equ     1Bh

        org     0100h
start:  ld      (orig_sp),sp
        ld      sp,stack_top
        call    main
        ld      sp,(orig_sp)
        ret

main:   ld      a,(FCB+1)
        cp      ' '
        jp      z,usage
        ld      hl,FCB+1
        ld      b,11
main_wild:
        ld      a,(hl)
        cp      '?'
        jp      z,usage
        inc     hl
        djnz    main_wild
        ld      de,FCB
        ld      c,15                    ; open: the file must not be there
        call    BDOS
        inc     a
        jr      z,main_make
        ld      de,msg_exists
        jp      print
main_make:
        ld      de,FCB
        ld      c,22                    ; make
        call    BDOS
        inc     a
        jr      nz,main_made
        ld      de,msg_full
        jp      print
main_made:
        xor     a
        ld      (FCB+32),a              ; the first record
        ld      de,sector
        ld      c,26                    ; set the DMA address
        call    BDOS
        ld      hl,0
        ld      (expected),hl
        ld      (filled),hl
        ld      (total),hl
        ld      de,msg_ready
        call    print
main_line:
        call    get_line
        jr      c,main_abort
        call    handle_line
        jr      c,main_line_bad
        ld      a,(finished)
        or      a
        jr      nz,main_finish
        ld      e,'.'
        call    put_char
        jr      main_line
main_line_bad:
        ld      a,(disk_failed)
        or      a
        jr      nz,main_disk
        ld      e,'!'
        call    put_char
        jr      main_line
main_finish:
        call    flush_last
        jr      c,main_disk
        ld      de,FCB
        ld      c,16                    ; close
        call    BDOS
        inc     a
        jr      z,main_disk
        ld      de,msg_ok
        call    print
        ld      a,(total_wrapped)
        or      a
        ld      de,msg_65536
        jr      nz,main_count
        ld      hl,(total)
        call    put_number
        jr      main_counted
main_count:
        call    print
main_counted:
        ld      de,msg_bytes
        jp      print
main_disk:
        ld      de,msg_disk
        call    print
        jr      erase
main_abort:
        ld      de,msg_aborted
        call    print
erase:  ld      de,FCB
        ld      c,16
        call    BDOS
        ld      de,FCB
        ld      c,19                    ; delete
        jp      BDOS
usage:  ld      de,msg_usage
        jp      print

; ---------- the console ----------
; One line from the console (without echo) into `line`, ended by a zero; the characters after LINE_MAX are lost
; (a record of more than 95 bytes is refused).
; Carry for Ctrl-C and ESC. A line with only CR or LF is skipped.
get_line:
        ld      hl,line
        ld      b,0
get_char:
        call    get_key
        cp      CTRL_C
        jr      z,get_stop
        cp      ESC
        jr      z,get_stop
        cp      13
        jr      z,get_end
        cp      10
        jr      z,get_end
        ld      c,a
        ld      a,b
        cp      LINE_MAX
        jr      nc,get_char
        ld      a,c
        ld      (hl),a
        inc     hl
        inc     b
        jr      get_char
get_end:
        ld      a,b
        or      a
        jr      z,get_char
        ld      (hl),0
        or      a
        ret
get_stop:
        scf
        ret

; A key from the console, waiting for it.
get_key:
        push    hl
        push    bc
get_wait:
        ld      c,6
        ld      e,0FFh
        call    BDOS
        or      a
        jr      z,get_wait
        pop     bc
        pop     hl
        ret

; The output goes through function 6 as the input does: functions 2 and 9 first read a waiting key
; into the BDOS (kbchar) where function 6 does not see it, and the line would lose characters.
put_char:
        ld      c,6
        jp      BDOS

print:  ld      a,(de)
        cp      '$'
        ret     z
        push    de
        ld      e,a
        call    put_char
        pop     de
        inc     de
        jr      print

; HL as a decimal number.
put_number:
        ld      de,10000
        call    put_digit_of
        ld      de,1000
        call    put_digit_of
        ld      de,100
        call    put_digit_of
        ld      de,10
        call    put_digit_of
        ld      a,l
        add     a,'0'
        ld      e,a
        jp      put_char
put_digit_of:
        ld      b,0
put_digit_sub:
        or      a
        sbc     hl,de
        jr      c,put_digit_done
        inc     b
        jr      put_digit_sub
put_digit_done:
        add     hl,de
        ld      a,(number_started)
        or      b
        ret     z
        ld      (number_started),a
        ld      a,b
        add     a,'0'
        ld      e,a
        push    hl
        call    put_char
        pop     hl
        ret

; ---------- the lines ----------
; The line in `line` as a record. Carry when it is wrong. A data record at the address that is expected
; goes to the file; one at a lower address (sent again) is good and is not stored twice.
handle_line:
        ld      hl,line
        ld      a,(hl)
        cp      ':'
        jr      nz,handle_bad
        inc     hl
        ld      c,0                     ; the sum of the bytes
        call    get_hex_byte            ; the length
        jr      c,handle_bad
        ld      (rec_length),a
        call    get_hex_byte            ; the address, high
        jr      c,handle_bad
        ld      d,a
        call    get_hex_byte
        jr      c,handle_bad
        ld      e,a
        ld      (rec_address),de
        call    get_hex_byte            ; the type
        jr      c,handle_bad
        ld      (rec_type),a
        ld      a,(rec_length)
        ld      b,a
        ld      de,record
        inc     b
        dec     b
        jr      z,handle_sum
handle_data:
        call    get_hex_byte
        jr      c,handle_bad
        ld      (de),a
        inc     de
        djnz    handle_data
handle_sum:
        call    get_hex_byte            ; the checksum: the sum of all with it is 0
        jr      c,handle_bad
        ld      a,c
        or      a
        jr      nz,handle_bad
        ld      a,(hl)
        or      a
        jr      nz,handle_bad
        ld      a,(rec_type)
        or      a
        jr      z,handle_store
        cp      1
        jr      nz,handle_bad
        ld      a,(rec_length)
        or      a
        jr      nz,handle_bad
        ld      a,1
        ld      (finished),a
        or      a
        ret
handle_store:
        ld      hl,(rec_address)
        ld      de,(expected)
        or      a
        sbc     hl,de
        jr      z,handle_write
        jr      c,handle_again          ; before what is expected: it is there already
handle_bad:
        scf
        ret
handle_again:
        or      a
        ret
handle_write:
        ld      a,(rec_length)
        ld      c,a
        ld      b,0
        ld      hl,record
        call    store_bytes
        ret

; Two hexadecimal digits at HL as a byte in A, added to the sum in C. Carry when they are not.
get_hex_byte:
        call    get_hex_digit
        ret     c
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        ld      (hex_high),a
        call    get_hex_digit
        ret     c
        push    hl
        ld      hl,hex_high
        or      (hl)
        pop     hl
        push    af
        add     a,c
        ld      c,a
        pop     af
        or      a
        ret
get_hex_digit:
        ld      a,(hl)
        inc     hl
        cp      'a'
        jr      c,digit_case
        cp      'z'+1
        jr      nc,digit_case
        sub     'a'-'A'
digit_case:
        sub     '0'
        ret     c
        cp      10
        jr      c,digit_ok
        sub     'A'-'0'
        jr      c,digit_bad
        cp      6
        jr      nc,digit_bad
        add     a,10
digit_ok:
        or      a
        ret
digit_bad:
        scf
        ret

; BC bytes from HL go after the bytes in `sector`; a full record of 128 goes to the file. Carry when
; the disk is full. expected and total grow.
store_bytes:
        ld      a,b
        or      c
        ret     z
        push    bc
        push    hl
        ld      hl,(filled)
        ld      de,sector
        add     hl,de
        ex      de,hl
        pop     hl
        ld      a,(hl)
        inc     hl
        ld      (de),a
        push    hl
        ld      hl,(filled)
        inc     hl
        ld      (filled),hl
        ld      hl,(expected)
        inc     hl
        ld      (expected),hl
        ld      hl,(total)
        inc     hl
        ld      (total),hl
        ld      a,h
        or      l
        jr      nz,store_counted
        ld      a,1
        ld      (total_wrapped),a       ; 65536 bytes: the number wrapped to 0
store_counted:
        ld      a,(filled)
        cp      128
        jr      nz,store_next
        call    write_record
        jr      nc,store_next
        pop     hl
        pop     bc
        ret
store_next:
        pop     hl
        pop     bc
        dec     bc
        jr      store_bytes

; The record in `sector` goes to the file, and it is empty again.
write_record:
        ld      de,FCB
        ld      c,21                    ; write the next record
        call    BDOS
        or      a
        ld      hl,0
        ld      (filled),hl
        ret     z
        ld      a,1
        ld      (disk_failed),a
        scf
        ret

; The end: the rest of the last record is Ctrl-Z, and it is written.
flush_last:
        ld      hl,(filled)
        ld      a,h
        or      l
        ret     z
        ld      de,sector
        add     hl,de
        ex      de,hl
        ld      hl,(filled)
        ld      a,l
        neg
        and     7Fh
        ld      c,a
        ld      b,0
        ld      a,1Ah
        ld      (de),a
        dec     bc
        ld      a,b
        or      c
        jr      z,flush_write
        push    de
        pop     hl
        inc     de
        ldir
flush_write:
        jp      write_record

msg_usage:      defm    "Usage: HEXIN [d:]file",13,10,'$'
msg_exists:     defm    "HEXIN: the file exists already",13,10,'$'
msg_full:       defm    "HEXIN: the directory is full",13,10,'$'
msg_disk:       defm    "HEXIN: the disk is full",13,10,'$'
msg_aborted:    defm    "HEXIN: stopped",13,10,'$'
msg_ready:      defm    "HEXIN: ready",13,10,'$'
msg_ok:         defm    13,10,"OK $"
msg_65536:      defm    "65536$"
msg_bytes:      defm    " bytes",13,10,'$'

LINE_MAX:       equ     200
orig_sp:        defw    0
expected:       defw    0
filled:         defw    0
total:          defw    0
rec_address:    defw    0
rec_length:     defb    0
rec_type:       defb    0
finished:       defb    0
disk_failed:    defb    0
total_wrapped:  defb    0
hex_high:       defb    0
number_started: defb    0
line:           defs    LINE_MAX+2
record:         defs    256
sector:         defs    128
                defs    64
stack_top:
