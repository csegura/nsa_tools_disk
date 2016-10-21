; File and console input and output for the small tools (src/tools/). The program defines
; BDOS (0005h) and the buffers that it uses. The routines of the readers and writers take IX
; (the reader or writer) and destroy the other registers, because each BDOS call does; the
; ones that write a number (decimal.asm) destroy IX too.
;
; A reader (R_SIZE bytes) has an FCB, the position in a buffer of one record, a flag for the
; end of the file, a flag for binary files (a Ctrl-Z is data) and the buffer. A writer
; (W_SIZE bytes) has an FCB, the position and the buffer.

R_POS:          equ     36
R_EOF:          equ     37
R_BINARY:       equ     38
R_BUFFER:       equ     39
R_SIZE:         equ     R_BUFFER+128
W_POS:          equ     36
W_BUFFER:       equ     37
W_SIZE:         equ     W_BUFFER+128
FCB_CR:         equ     32

; The bytes 12 to 35 of the FCB at IX are cleared: a name that was parsed has to have them
; so for the BDOS (the allocation map and the record counters).
fcb_clear_tail:
        push    ix
        pop     hl
        ld      bc,12
        add     hl,bc
        ld      b,24
        xor     a
fcb_clear_byte:
        ld      (hl),a
        inc     hl
        djnz    fcb_clear_byte
        ret

; IX = a reader whose FCB has the name. Carry when the file is not there. The reader is a
; reader of text; a program that wants all the bytes sets R_BINARY after this.
rd_open:
        push    ix
        pop     de
        ld      c,15
        call    BDOS
        inc     a
        jr      nz,rd_opened
        scf
        ret
rd_opened:
        xor     a
        ld      (ix+FCB_CR),a
        ld      (ix+R_EOF),a
        ld      (ix+R_BINARY),a
        ld      a,128
        ld      (ix+R_POS),a
        or      a
        ret

; The next byte of the file in A; carry at the end. In a text file a Ctrl-Z or a zero is the
; end (the last record is filled with them, or with zeros if the file was made on the host);
; in a binary one (R_BINARY) they are bytes.
rd_getc:
        ld      a,(ix+R_EOF)
        or      a
        jr      nz,rd_end
        ld      a,(ix+R_POS)
        cp      128
        jr      c,rd_have
        push    ix
        pop     hl
        ld      de,R_BUFFER
        add     hl,de
        ex      de,hl
        ld      c,26
        call    BDOS
        push    ix
        pop     de
        ld      c,20
        call    BDOS
        or      a
        jr      nz,rd_end_set
        xor     a
        ld      (ix+R_POS),a
rd_have:
        ld      e,(ix+R_POS)
        ld      d,0
        push    ix
        pop     hl
        add     hl,de
        ld      de,R_BUFFER
        add     hl,de
        ld      a,(hl)
        inc     (ix+R_POS)
        or      a
        jr      z,rd_special
        cp      1Ah
        jr      nz,rd_ok
rd_special:
        ld      b,a
        ld      a,(ix+R_BINARY)
        or      a
        ld      a,b
        jr      nz,rd_ok
        dec     (ix+R_POS)
        jr      rd_end_set
rd_ok:
        or      a
        ret
rd_end_set:
        ld      a,1
        ld      (ix+R_EOF),a
rd_end:
        scf
        ret

; The next line of a text file goes to DE, ended by a zero: carriage returns are dropped
; and a line that is longer than B-1 characters is cut. Carry when there is no line.
rd_line:
        ld      (rd_pos),de
        dec     b
        ld      a,b
        ld      (rd_room),a
        xor     a
        ld      (rd_any),a
rd_line_next:
        call    rd_getc
        jr      c,rd_line_eof
        ld      b,a
        ld      a,1
        ld      (rd_any),a
        ld      a,b
        cp      0Ah
        jr      z,rd_line_done
        cp      0Dh
        jr      z,rd_line_next
        ld      a,(rd_room)
        or      a
        jr      nz,rd_line_room
        ld      a,1
        ld      (rd_cut),a
        jr      rd_line_next
rd_line_room:
        dec     a
        ld      (rd_room),a
        ld      hl,(rd_pos)
        ld      (hl),b
        inc     hl
        ld      (rd_pos),hl
        jr      rd_line_next
rd_line_eof:
        ld      a,(rd_any)
        or      a
        jr      nz,rd_line_done
        ld      hl,(rd_pos)
        ld      (hl),0
        scf
        ret
rd_line_done:
        ld      hl,(rd_pos)
        ld      (hl),0
        or      a
        ret
rd_pos:         defw    0
rd_room:        defb    0
rd_any:         defb    0
rd_cut:         defb    0               ; Set when a line was longer than the buffer

; IX = a writer whose FCB has the name. The file is made (an old one is erased first by
; the caller if it wants). Carry when the directory is full.
wr_create:
        push    ix
        pop     de
        ld      c,22
        call    BDOS
        inc     a
        jr      nz,wr_created
        scf
        ret
wr_created:
        xor     a
        ld      (ix+FCB_CR),a
        ld      (ix+W_POS),a
        ret

; Write the byte A. Carry when the disk is full.
wr_putc:
        ld      b,a
        ld      e,(ix+W_POS)
        ld      d,0
        push    ix
        pop     hl
        add     hl,de
        ld      de,W_BUFFER
        add     hl,de
        ld      (hl),b
        inc     (ix+W_POS)
        ld      a,(ix+W_POS)
        cp      128
        jr      nc,wr_flush
        or      a
        ret
; Write the buffer as one record.
wr_flush:
        xor     a
        ld      (ix+W_POS),a
        push    ix
        pop     hl
        ld      de,W_BUFFER
        add     hl,de
        ex      de,hl
        ld      c,26
        call    BDOS
        push    ix
        pop     de
        ld      c,21
        call    BDOS
        or      a
        ret     z
        scf
        ret

; Finish the file: the rest of the last record is filled with Ctrl-Z, and the file is
; closed. Carry when the disk is full or the file cannot be closed.
wr_close:
        ld      a,(ix+W_POS)
        or      a
        jr      z,wr_closing
wr_fill:
        ld      a,1Ah
        call    wr_putc
        ret     c
        ld      a,(ix+W_POS)
        or      a
        jr      nz,wr_fill
wr_closing:
        push    ix
        pop     de
        ld      c,16
        call    BDOS
        inc     a
        jr      z,wr_close_failed
        or      a
        ret
wr_close_failed:
        scf
        ret

; ---------- the directory ----------
; The directory entries that a pattern names (a file has one for each 16K or 32K). dir_first takes DE = an FCB with the pattern
; (the drive, the name and the type, with ? for any); the extent byte is set here. They
; return HL = the directory entry (32 bytes, in dir_buffer) and carry at the end; the
; entries that are erased are left out. The user
; area is the current one (BDOS function 32).
dir_first:
        ld      (dir_pattern),de
        ld      hl,12
        add     hl,de
        ld      (hl),'?'
        ld      de,dir_buffer
        ld      c,26
        call    BDOS
        ld      de,(dir_pattern)
        ld      c,17
        call    BDOS
        jr      dir_check
dir_next:
        ld      de,dir_buffer
        ld      c,26
        call    BDOS
        ld      de,(dir_pattern)
        ld      c,18
        call    BDOS
dir_check:
        cp      0FFh
        jr      nz,dir_found
        scf
        ret
dir_found:
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,dir_buffer
        add     hl,de
        ld      a,(hl)
        cp      0E5h
        jr      z,dir_next
        or      a
        ret
dir_pattern:    defw    0

; Copy the name of the directory entry at HL to the FCB at DE: the drive 0, the name and
; the type without the attribute bits, and the other bytes zero.
fcb_from_entry:
        xor     a
        ld      (de),a
        inc     de
        inc     hl
        ld      b,11
entry_name_byte:
        ld      a,(hl)
        and     7Fh
        ld      (de),a
        inc     hl
        inc     de
        djnz    entry_name_byte
        ld      b,24
        xor     a
entry_zero_byte:
        ld      (de),a
        inc     de
        djnz    entry_zero_byte
        ret

; ---------- the console ----------
print:  ld      c,9
        jp      BDOS

put_char:
        ld      c,2
        jp      BDOS

print_crlf:
        ld      de,crlf_text
        jr      print
crlf_text:      defm    13,10,'$'

; The text at HL, ended by a zero.
put_text:
        ld      a,(hl)
        or      a
        ret     z
        inc     hl
        push    hl
        ld      e,a
        call    put_char
        pop     hl
        jr      put_text

; The decimal number HL, without blanks (numbuf and line_out are the program's).
put_number:
        ld      de,number_text
        call    emit_number
        xor     a
        ld      (de),a
        ld      hl,number_text
        jr      put_text
number_text:    defs    8,0

; The name and type of the FCB or directory entry at HL (11 bytes, the name first) as
; NAME.EXT, to the console.
put_file_name:
        ld      b,8
        call    put_name_part
        ld      a,(hl)
        cp      ' '
        ret     z
        push    hl
        ld      e,'.'
        call    put_char
        pop     hl
        ld      b,3
put_name_part:
        ld      a,(hl)
        inc     hl
        cp      ' '
        jr      z,put_name_skip
        and     7Fh
        push    hl
        push    bc
        ld      e,a
        call    put_char
        pop     bc
        pop     hl
put_name_skip:
        djnz    put_name_part
        ret

; The byte A of a text to the console: a line feed that does not follow a carriage return
; gets one. Ctrl-Z and the other controls except tab, CR and LF are left out.
put_text_byte:
        cp      0Ah
        jr      z,put_text_lf
        cp      0Dh
        jr      z,put_text_cr
        cp      9
        jr      z,put_text_plain
        cp      ' '
        ret     c
put_text_plain:
        ld      e,a
        xor     a
        ld      (last_was_cr),a
        jp      put_char
put_text_cr:
        ld      a,1
        ld      (last_was_cr),a
        ld      e,0Dh
        jp      put_char
put_text_lf:
        ld      a,(last_was_cr)
        or      a
        jr      nz,put_text_lf_only
        ld      e,0Dh
        call    put_char
put_text_lf_only:
        xor     a
        ld      (last_was_cr),a
        ld      e,0Ah
        jp      put_char
last_was_cr:    defb    0

; HL as a decimal number in five columns with blanks in front, to the console.
put_number5:
        ld      de,number_text
        call    emit_decimal5
        xor     a
        ld      (de),a
        ld      hl,number_text
        jp      put_text

; The message at HL, ended by a zero, then the name that was being used.
put_message:
        jp      put_text

; The byte A as two hexadecimal digits, and HL as four, to the console.
put_hex16:
        push    hl
        ld      a,h
        call    put_hex8
        pop     hl
        ld      a,l
put_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    put_nibble
        pop     af
put_nibble:
        and     0Fh
        add     a,'0'
        cp      '9'+1
        jr      c,put_digit
        add     a,'A'-'0'-10
put_digit:
        ld      e,a
        jp      put_char

; Compare the zero-ended texts at HL and DE: Z when they are the same.
text_equal:
        ld      a,(de)
        cp      (hl)
        ret     nz
        or      a
        ret     z
        inc     hl
        inc     de
        jr      text_equal

; Make the user area A (0 to 15) the current one.
set_user:
        ld      e,a
        ld      c,32
        jp      BDOS

; A = the current user area.
get_user:
        ld      e,0FFh
        ld      c,32
        jp      BDOS
