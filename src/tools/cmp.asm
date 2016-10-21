; CMP: compare two files byte by byte.
;
;     CMP [-l] [-t] [d:]file1 [d:]file2
;
; It says where the first difference is, with the bytes. -l shows the first 20 differences
; and says when there are more. The files are compared as they are, to the end of their last record
; (so the bytes after the end of a text file, which the editors fill differently, are
; compared as well); -t stops at the first Ctrl-Z, as a text file does.

BDOS:           equ     0005h
TAIL:           equ     0080h
LIST_MAX:       equ     20

        org     0100h
start:  ld      (orig_sp),sp
        ld      sp,stack_top
        ld      hl,flag_list
        ld      de,flag_list+1
        ld      bc,flags_end-flag_list-1
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
        ld      de,reader_one
        or      a
        jr      z,main_parse
        ld      de,reader_two
main_parse:
        ld      hl,word
        call    parse_fcb
        ld      hl,names
        inc     (hl)
        jr      main_word
main_run:
        ld      a,(names)
        cp      2
        jr      z,compare
usage:  ld      de,msg_usage
        jp      print

tool_option:
        ld      hl,flag_list
        cp      'L'
        jr      z,option_set
        ld      hl,flag_text
        cp      'T'
        scf
        ret     nz
option_set:
        ld      (hl),1
        or      a
        ret

compare:
        ld      ix,reader_one
        call    fcb_clear_tail
        ld      ix,reader_two
        call    fcb_clear_tail
        ld      ix,reader_one
        call    rd_open
        jp      c,open_failed
        ld      ix,reader_two
        call    rd_open
        jp      c,open_failed
        ld      a,(flag_text)
        xor     1
        ld      (reader_one+R_BINARY),a
        ld      (reader_two+R_BINARY),a
        ld      hl,0
        ld      (offset),hl
        xor     a
        ld      (offset+2),a
        ld      (differences),a
compare_next:
        ld      ix,reader_one
        call    rd_getc
        ld      (byte_one),a
        ld      a,0
        rla
        ld      (end_one),a
        ld      ix,reader_two
        call    rd_getc
        ld      (byte_two),a
        ld      a,0
        rla
        ld      (end_two),a
        ld      hl,end_one
        ld      a,(end_two)
        or      (hl)
        jr      z,compare_bytes
        ld      a,(end_one)
        ld      hl,end_two
        cp      (hl)
        jr      z,compare_done
        ld      de,msg_shorter_one
        ld      a,(end_one)
        or      a
        jr      nz,compare_shorter
        ld      de,msg_shorter_two
compare_shorter:
        call    print
        call    put_offset
        ld      de,msg_bytes
        call    print
        ld      a,1
        ld      (differences),a
        jr      compare_done
compare_bytes:
        ld      a,(byte_one)
        ld      hl,byte_two
        cp      (hl)
        jr      z,compare_same
        ld      a,(flag_list)
        or      a
        jr      nz,compare_listing
        call    report
        jr      compare_done
compare_listing:
        ld      a,(differences)
        cp      LIST_MAX
        jr      c,compare_report
        ld      a,0FFh
        ld      (differences),a
        jr      compare_done
compare_report:
        call    report
        jr      compare_same
compare_same:
        ld      hl,(offset)
        inc     hl
        ld      (offset),hl
        ld      a,h
        or      l
        jp      nz,compare_next
        ld      hl,offset+2
        inc     (hl)
        jp      compare_next
compare_done:
        ld      a,(differences)
        or      a
        jr      nz,compare_summary
        ld      de,msg_same
        jp      print
compare_summary:
        cp      0FFh
        ret     nz
        ld      de,msg_more
        jp      print

open_failed:
        ld      de,msg_no_file
        jp      print

; One difference: the offset (in hex) and the two bytes.
report:
        ld      hl,differences
        inc     (hl)
        call    put_offset
        ld      e,' '
        call    put_char
        ld      a,(byte_one)
        call    put_hex8
        ld      e,' '
        call    put_char
        ld      a,(byte_two)
        call    put_hex8
        jp      print_crlf

put_offset:
        ld      a,(offset+2)
        call    put_hex8
        ld      hl,(offset)
        jp      put_hex16

        include "cpm_fcb.asm"
        include "cpm_args.asm"
        include "cpm_io.asm"
        include "decimal.asm"

msg_usage:      defm "Usage: CMP [-l] [-t] [d:]file1 [d:]file2",13,10,'$'
msg_no_file:    defm "CMP: a file is not there",13,10,'$'
msg_same:       defm "The files are the same",13,10,'$'
msg_more:       defm "More differences are not shown",13,10,'$'
msg_shorter_one: defm "The first file ends at offset ",'$'
msg_shorter_two: defm "The second file ends at offset ",'$'
msg_bytes:      defm 13,10,'$'
args:           defw 0

image_end:
flag_list:      equ     image_end
flag_text:      equ     flag_list+1
names:          equ     flag_text+1
differences:    equ     names+1
byte_one:       equ     differences+1
byte_two:       equ     byte_one+1
end_one:        equ     byte_two+1
end_two:        equ     end_one+1
flags_end:      equ     end_two+1
orig_sp:        equ     flags_end
args_pos:       equ     orig_sp+2
offset:         equ     args_pos+2
numbuf:         equ     offset+3
work:           equ     numbuf+8
word:           equ     work+130
dir_buffer:     equ     word+64
reader_one:     equ     dir_buffer+128
reader_two:     equ     reader_one+R_SIZE
stack_low:      equ     reader_two+R_SIZE
stack_top:      equ     stack_low+128
