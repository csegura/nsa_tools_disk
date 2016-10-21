; CRLF: change the line ends of a text file, and expand its tabs.
;
;     CRLF [-u] [-f] [-t N] [d:]in [d:]out
;
; The line ends of the file in (CR LF, LF or a CR alone) become CR LF, which is what CP/M
; programs expect, or only LF with -u (what the files of Unix have). -t N expands the tabs
; to N columns. The file out must not be there unless -f is given. A Ctrl-Z ends the text
; of the file in; the file out is filled to a record with Ctrl-Z.

BDOS:           equ     0005h
TAIL:           equ     0080h

        org     0100h
start:  ld      (orig_sp),sp
        ld      sp,stack_top
        ld      hl,flag_unix
        ld      de,flag_unix+1
        ld      bc,flags_end-flag_unix-1
        ld      (hl),0
        ldir
        call    main
        ld      sp,(orig_sp)
        ret

main:   call    args_init
main_word:
        call    next_word
        jr      c,main_run
        ld      a,(word)
        cp      '-'
        jr      nz,main_name
        call    parse_options
        jr      nc,main_word
        jr      usage
main_name:
        ld      a,(names)
        cp      2
        jr      nc,usage
        ld      de,reader
        or      a
        jr      z,main_parse
        ld      de,writer
main_parse:
        ld      hl,word
        call    parse_fcb
        ld      hl,names
        inc     (hl)
        jr      main_word
main_run:
        ld      a,(names)
        cp      2
        jr      z,convert
usage:  ld      de,msg_usage
        jp      print

; -u -f and -t N
tool_option:
        cp      'U'
        jr      nz,option_f
        ld      a,1
        ld      (flag_unix),a
        or      a
        ret
option_f:
        cp      'F'
        jr      nz,option_t
        ld      a,1
        ld      (flag_force),a
        or      a
        ret
option_t:
        cp      'T'
        scf
        ret     nz
        call    next_word
        ret     c
        ld      hl,word
        call    parse_decimal
        ret     c
        ld      a,d
        or      a
        scf
        ret     nz
        ld      a,e
        cp      33
        ccf
        ret     c
        ld      (tab_width),a
        or      a
        ret

convert:
        ld      ix,reader
        call    fcb_clear_tail
        ld      ix,writer
        call    fcb_clear_tail
        ld      hl,reader+1
        call    check_name
        jr      c,usage
        ld      hl,writer+1
        call    check_name
        jr      c,usage
        call    same_file
        jr      nz,convert_names_ok
        ld      de,msg_same
        jp      print
convert_names_ok:
        ld      ix,reader
        call    rd_open
        jr      nc,convert_opened
        ld      de,msg_no_input
        jp      print
convert_opened:
        ld      a,(flag_force)
        or      a
        jr      z,convert_new
        ld      de,writer
        ld      c,19
        call    BDOS
convert_new:
        ld      de,writer
        ld      c,15
        call    BDOS
        inc     a
        jr      z,convert_make
        ld      de,msg_exists
        jp      print
convert_make:
        ld      ix,writer
        call    wr_create
        jr      nc,convert_loop_start
        ld      de,msg_full
        jp      print
convert_loop_start:
        xor     a
        ld      (column),a
        ld      (pending_cr),a
convert_loop:
        ld      ix,reader
        call    rd_getc
        jr      c,convert_end
        ld      (this_byte),a
        cp      0Dh
        jr      nz,convert_not_cr
        ld      a,(pending_cr)
        or      a
        call    nz,put_eol
        jr      c,convert_failed
        ld      a,1
        ld      (pending_cr),a
        jr      convert_loop
convert_not_cr:
        cp      0Ah
        jr      nz,convert_other
        xor     a
        ld      (pending_cr),a
        call    put_eol
        jr      c,convert_failed
        jr      convert_loop
convert_other:
        ld      a,(pending_cr)
        or      a
        jr      z,convert_char
        xor     a
        ld      (pending_cr),a
        call    put_eol
        jr      c,convert_failed
convert_char:
        ld      a,(this_byte)
        cp      9
        jr      nz,convert_plain
        ld      a,(tab_width)
        or      a
        jr      z,convert_plain
        call    put_tab
        jr      c,convert_failed
        jr      convert_loop
convert_plain:
        ld      a,(this_byte)
        call    put_byte
        jr      c,convert_failed
        jr      convert_loop
convert_end:
        ld      a,(pending_cr)
        or      a
        call    nz,put_eol
        jr      c,convert_failed
        ld      ix,writer
        call    wr_close
        ret     nc
convert_failed:
        ld      de,msg_full
        jp      print

; Write the byte A and count the column (mod the tab width, so it cannot wrap wrongly).
put_byte:
        ld      ix,writer
        call    wr_putc
        ret     c
        ld      a,(tab_width)
        or      a
        ret     z
        ld      hl,column
        inc     (hl)
        cp      (hl)
        jr      nz,put_byte_done
        ld      (hl),0
put_byte_done:
        or      a
        ret

; The line end: CR LF, or LF with -u.
put_eol:
        ld      a,(flag_unix)
        or      a
        jr      nz,put_eol_lf
        ld      ix,writer
        ld      a,0Dh
        call    wr_putc
        ret     c
put_eol_lf:
        ld      ix,writer
        ld      a,0Ah
        call    wr_putc
        ret     c
        xor     a
        ld      (column),a
        ret

; Blanks up to the next multiple of the tab width.
put_tab:
        ld      a,' '
        call    put_byte
        ret     c
        ld      a,(column)
        or      a
        jr      nz,put_tab
        ret

; Z when the input and the output are the same file: the drive and the name (the current
; drive is 0 in both, so a name on drive A: is not told from the same name without a drive
; when A: is the current drive; the check is made with what the FCBs say).
same_file:
        ld      a,(reader)
        ld      hl,writer
        cp      (hl)
        ret     nz
        ld      hl,reader+1
        ld      de,writer+1
        ld      b,11
same_file_byte:
        ld      a,(de)
        cp      (hl)
        ret     nz
        inc     hl
        inc     de
        djnz    same_file_byte
        xor     a
        ret

; Carry when the name at HL (the name and the type) has * or ? or no name.
check_name:
        ld      a,(hl)
        cp      ' '
        scf
        ret     z
        ld      b,11
check_wild:
        ld      a,(hl)
        cp      '?'
        scf
        ret     z
        inc     hl
        djnz    check_wild
        or      a
        ret

        include "cpm_fcb.asm"
        include "cpm_args.asm"
        include "cpm_io.asm"
        include "decimal.asm"

msg_usage:      defm "Usage: CRLF [-u] [-f] [-t N] [d:]in [d:]out",13,10,'$'
msg_same:       defm "CRLF: the input and the output are the same file",13,10,'$'
msg_no_input:   defm "CRLF: the input file is not there",13,10,'$'
msg_exists:     defm "CRLF: the output file is there (-f replaces it)",13,10,'$'
msg_full:       defm "CRLF: the disk or the directory is full",13,10,'$'
args:           defw 0

image_end:
flag_unix:      equ     image_end
flag_force:     equ     flag_unix+1
tab_width:      equ     flag_force+1
names:          equ     tab_width+1
column:         equ     names+1
pending_cr:     equ     column+1
this_byte:      equ     pending_cr+1
flags_end:      equ     this_byte+1
orig_sp:        equ     flags_end
args_pos:       equ     orig_sp+2
numbuf:         equ     args_pos+2
work:           equ     numbuf+8
word:           equ     work+130
dir_buffer:     equ     word+64
reader:         equ     dir_buffer+128
writer:         equ     reader+R_SIZE
stack_low:      equ     writer+W_SIZE
stack_top:      equ     stack_low+128
