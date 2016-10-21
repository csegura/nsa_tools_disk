; CAT: write files to the console, one after the other.
;
;     CAT [-n] [d:]file ...
;
; -n numbers the lines. A file name may have * and ?. The tail of the files that are text
; ends at the first Ctrl-Z.

BDOS:           equ     0005h
TAIL:           equ     0080h
MAX_TEMP:      equ     40
MAX_ALL:        equ     40

        org     0100h
start:  ld      (orig_sp),sp
        ld      sp,stack_top
        ld      hl,flag_numbers
        ld      de,flag_numbers+1
        ld      bc,flags_end-flag_numbers-1
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

tool_option:
        cp      'N'
        scf
        ret     nz
        ld      a,1
        ld      (flag_numbers),a
        or      a
        ret

; The open file, to the console.
tool_file:
        ld      hl,1
        ld      (line_number),hl
        ld      a,1
        ld      (line_start),a
show_char:
        ld      ix,reader
        call    rd_getc
        ret     c
        ld      (last_byte),a
        ld      a,(line_start)
        or      a
        jr      z,show_put
        ld      a,(flag_numbers)
        or      a
        jr      z,show_put
        ld      hl,(line_number)
        call    put_number5
        ld      e,' '
        call    put_char
        ld      hl,(line_number)
        inc     hl
        ld      (line_number),hl
show_put:
        xor     a
        ld      (line_start),a
        ld      a,(last_byte)
        cp      0Ah
        jr      nz,show_out
        ld      a,1
        ld      (line_start),a
show_out:
        ld      a,(last_byte)
        call    put_text_byte
        jr      show_char

        include "cpm_fcb.asm"
        include "cpm_args.asm"
        include "cpm_files.asm"
        include "cpm_process.asm"
        include "cpm_io.asm"
        include "decimal.asm"

msg_usage:      defm "Usage: CAT [-n] [d:]file ...",13,10,'$'
msg_not_found:  defm ": not found",13,10,0
args:           defw 0

image_end:
flag_numbers:   equ     image_end
all_count:      equ     flag_numbers+1
missing:        equ     all_count+1
line_start:     equ     missing+1
last_byte:      equ     line_start+1
flags_end:      equ     last_byte+1
orig_sp:        equ     flags_end
args_pos:       equ     orig_sp+2
line_number:    equ     args_pos+2
numbuf:         equ     line_number+2
work:           equ     numbuf+8
word:           equ     work+130
pattern:        equ     word+64
dir_buffer:     equ     pattern+36
temp_files:     equ     dir_buffer+128
all_files:      equ     temp_files+MAX_TEMP*12
current_entry:  equ     all_files+MAX_ALL*13
reader:         equ     current_entry+2
stack_low:      equ     reader+R_SIZE
stack_top:      equ     stack_low+128
