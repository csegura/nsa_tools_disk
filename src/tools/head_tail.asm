; HEAD and TAIL: the first or the last lines of files. One source, built twice (TAIL is
; assembled with IS_TAIL set to 1).
;
;     HEAD [-n N] [d:]file ...        the first N lines (10 if there is no -n)
;     TAIL [-n N] [d:]file ...        the last N lines
;
; With more than one file each one has a title line. TAIL reads a file twice: to count its
; lines, and then to write the last ones.

BDOS:           equ     0005h
TAIL:           equ     0080h
MAX_TEMP:      equ     40
MAX_ALL:        equ     40
LINES_DEFAULT:  equ     10

        org     0100h
start:  ld      (orig_sp),sp
        ld      sp,stack_top
        ld      hl,flags
        ld      de,flags+1
        ld      bc,flags_end-flags-1
        ld      (hl),0
        ldir
        ld      hl,LINES_DEFAULT
        ld      (wanted),hl
        call    main
        ld      sp,(orig_sp)
        ret

main:   call    args_init
main_word:
        call    next_word
        jr      c,main_run
        ld      a,(word)
        cp      '-'
        jr      nz,main_file
        call    parse_options
        jr      nc,main_word
        jr      usage
main_file:
        call    gather_word
        jr      main_word
main_run:
        ld      a,(all_count)
        or      a
        jr      z,main_none
        jp      process_all
main_none:
        ld      a,(missing)
        or      a
        ret     nz
usage:  ld      de,msg_usage
        jp      print

; -n N: the number of lines is the next word.
tool_option:
        cp      'N'
        scf
        ret     nz
        call    next_word
        ret     c
        ld      hl,word
        call    parse_decimal
        ret     c
        ld      (wanted),de
        or      a
        ret

; The open file: the title line, when there is more than one file; then the lines.
tool_file:
        ld      a,(all_count)
        cp      2
        jr      c,show_lines
        ld      a,(title_given)
        or      a
        jr      z,show_title
        call    print_crlf
show_title:
        ld      a,1
        ld      (title_given),a
        ld      hl,txt_title_start
        call    put_text
        ld      hl,(current_entry)
        inc     hl
        call    put_file_name
        ld      hl,txt_title_end
        call    put_text
show_lines:
        ld      a,IS_TAIL
        or      a
        jr      nz,tail_lines
        ld      hl,(wanted)
        ld      (to_write),hl
head_char:
        ld      hl,(to_write)
        ld      a,h
        or      l
        ret     z
        ld      ix,reader
        call    rd_getc
        ret     c
        ld      (last_byte),a
        call    put_text_byte
        ld      a,(last_byte)
        cp      0Ah
        jr      nz,head_char
        ld      hl,(to_write)
        dec     hl
        ld      (to_write),hl
        jr      head_char

; The lines of the file are counted, the file is opened again, and the lines before the last
; N are skipped.
tail_lines:
        ld      hl,0
        ld      (total_count),hl
        xor     a
        ld      (last_byte),a
tail_count:
        ld      ix,reader
        call    rd_getc
        jr      c,tail_counted
        ld      (last_byte),a
        cp      0Ah
        jr      nz,tail_count
        ld      hl,(total_count)
        inc     hl
        ld      (total_count),hl
        jr      tail_count
tail_counted:
        ld      a,(last_byte)
        or      a
        jr      z,tail_start
        cp      0Ah
        jr      z,tail_start
        ld      hl,(total_count)
        inc     hl
        ld      (total_count),hl
tail_start:
        ld      hl,(total_count)
        ld      de,(wanted)
        or      a
        sbc     hl,de
        jr      nc,tail_skip_set
        ld      hl,0
tail_skip_set:
        ld      (skip_count),hl
        ld      hl,(current_entry)
        ld      ix,reader
        call    open_gathered
        ret     c
tail_skip:
        ld      hl,(skip_count)
        ld      a,h
        or      l
        jr      z,tail_write
        ld      ix,reader
        call    rd_getc
        ret     c
        cp      0Ah
        jr      nz,tail_skip
        ld      hl,(skip_count)
        dec     hl
        ld      (skip_count),hl
        jr      tail_skip
tail_write:
        ld      ix,reader
        call    rd_getc
        ret     c
        call    put_text_byte
        jr      tail_write

        include "cpm_fcb.asm"
        include "cpm_args.asm"
        include "cpm_files.asm"
        include "cpm_process.asm"
        include "cpm_io.asm"
        include "decimal.asm"

msg_usage:      defm "Usage: HEAD/TAIL [-n N] [d:]file ...",13,10,'$'
msg_not_found:  defm ": not found",13,10,0
txt_title_start: defm "==> ",0
txt_title_end:  defm " <==",13,10,0
args:           defw 0

image_end:
flags:          equ     image_end
all_count:      equ     flags
missing:        equ     all_count+1
title_given:    equ     missing+1
last_byte:      equ     title_given+1
flags_end:      equ     last_byte+1
orig_sp:        equ     flags_end
args_pos:       equ     orig_sp+2
current_entry:  equ     args_pos+2
wanted:         equ     current_entry+2
to_write:       equ     wanted+2
total_count:    equ     to_write+2
skip_count:     equ     total_count+2
numbuf:         equ     skip_count+2
work:           equ     numbuf+8
word:           equ     work+130
pattern:        equ     word+64
dir_buffer:     equ     pattern+36
temp_files:     equ     dir_buffer+128
all_files:      equ     temp_files+MAX_TEMP*12
reader:         equ     all_files+MAX_ALL*13
stack_low:      equ     reader+R_SIZE
stack_top:      equ     stack_low+128
