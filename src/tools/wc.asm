; WC: count the lines, words and bytes of files.
;
;     WC [-l] [-w] [-c] [d:]file ...
;
; Without an option all three are shown. The count stops at 65535. The bytes are those
; before the first Ctrl-Z of the file (a text file is filled with them to a record).

BDOS:           equ     0005h
TAIL:           equ     0080h
MAX_TEMP:      equ     40
MAX_ALL:        equ     40

        org     0100h
start:  ld      (orig_sp),sp
        ld      sp,stack_top
        ld      hl,flag_lines
        ld      de,flag_lines+1
        ld      bc,flags_end-flag_lines-1
        ld      (hl),0
        ldir
        call    main
        ld      sp,(orig_sp)
        ret

main:   ld      hl,0
        ld      (total_lines),hl
        ld      (total_words),hl
        ld      (total_bytes),hl
        call    args_init
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
        call    process_all
        ld      a,(all_count)
        cp      2
        ret     c
        ld      hl,(total_lines)
        ld      (count_lines),hl
        ld      hl,(total_words)
        ld      (count_words),hl
        ld      hl,(total_bytes)
        ld      (count_bytes),hl
        ld      hl,msg_total
        jp      put_counts
main_none:
        ld      a,(missing)
        or      a
        ret     nz
usage:  ld      de,msg_usage
        jp      print

; The open file: count, add to the totals, show.
tool_file:
        call    count_file
        ld      hl,(current_entry)
        inc     hl
        jp      put_counts

tool_option:
        ld      hl,flag_lines
        cp      'L'
        jr      z,option_set
        ld      hl,flag_words
        cp      'W'
        jr      z,option_set
        ld      hl,flag_bytes
        cp      'C'
        scf
        ret     nz
option_set:
        ld      (hl),1
        or      a
        ret

; Count the open file in count_*, and add them to the totals.
count_file:
        ld      hl,0
        ld      (count_lines),hl
        ld      (count_words),hl
        ld      (count_bytes),hl
        xor     a
        ld      (in_word),a
        ld      (last_byte),a
count_char:
        ld      ix,reader
        call    rd_getc
        jr      c,count_end
        ld      (last_byte),a
        ld      hl,(count_bytes)
        call    increment
        ld      (count_bytes),hl
        ld      a,(last_byte)
        cp      0Ah
        jr      nz,count_not_line
        ld      hl,(count_lines)
        call    increment
        ld      (count_lines),hl
count_not_line:
        ld      a,(last_byte)
        cp      '!'
        jr      nc,count_letter
        xor     a
        ld      (in_word),a
        jr      count_char
count_letter:
        ld      a,(in_word)
        or      a
        jr      nz,count_char
        inc     a
        ld      (in_word),a
        ld      hl,(count_words)
        call    increment
        ld      (count_words),hl
        jr      count_char
count_end:
        ld      a,(last_byte)
        or      a
        jr      z,count_totals
        cp      0Ah
        jr      z,count_totals
        ld      hl,(count_lines)
        call    increment
        ld      (count_lines),hl
count_totals:
        ld      hl,(count_lines)
        ld      de,(total_lines)
        call    add_saturated
        ld      (total_lines),hl
        ld      hl,(count_words)
        ld      de,(total_words)
        call    add_saturated
        ld      (total_words),hl
        ld      hl,(count_bytes)
        ld      de,(total_bytes)
        call    add_saturated
        ld      (total_bytes),hl
        ret

; HL + 1, but not past 65535.
increment:
        inc     hl
        ld      a,h
        or      l
        ret     nz
        dec     hl
        ret

; HL + DE, but not past 65535.
add_saturated:
        add     hl,de
        ret     nc
        ld      hl,0FFFFh
        ret

; The counts that are asked for, then the name at HL (or the text at HL for the total).
put_counts:
        push    hl
        ld      a,(flag_lines)
        ld      hl,flag_words
        or      (hl)
        ld      hl,flag_bytes
        or      (hl)
        jr      nz,put_flags_set
        ld      a,1
        ld      (flag_lines),a
        ld      (flag_words),a
        ld      (flag_bytes),a
put_flags_set:
        ld      a,(flag_lines)
        or      a
        jr      z,put_words
        ld      hl,(count_lines)
        call    put_number5
        ld      e,' '
        call    put_char
put_words:
        ld      a,(flag_words)
        or      a
        jr      z,put_bytes
        ld      hl,(count_words)
        call    put_number5
        ld      e,' '
        call    put_char
put_bytes:
        ld      a,(flag_bytes)
        or      a
        jr      z,put_name
        ld      hl,(count_bytes)
        call    put_number5
        ld      e,' '
        call    put_char
put_name:
        pop     hl
        ld      a,h
        cp      msg_total/256
        jr      nz,put_name_file
        ld      a,l
        cp      msg_total&255
        jr      nz,put_name_file
        call    put_text
        jp      print_crlf
put_name_file:
        call    put_file_name
        jp      print_crlf

        include "cpm_fcb.asm"
        include "cpm_args.asm"
        include "cpm_files.asm"
        include "cpm_process.asm"
        include "cpm_io.asm"
        include "decimal.asm"

msg_usage:      defm "Usage: WC [-l] [-w] [-c] [d:]file ...",13,10,'$'
msg_not_found:  defm ": not found",13,10,0
msg_total:      defm "total",0
args:           defw 0

image_end:
flag_lines:     equ     image_end
flag_words:     equ     flag_lines+1
flag_bytes:     equ     flag_words+1
all_count:      equ     flag_bytes+1
missing:        equ     all_count+1
in_word:        equ     missing+1
last_byte:      equ     in_word+1
flags_end:      equ     last_byte+1
orig_sp:        equ     flags_end
args_pos:       equ     orig_sp+2
current_entry:  equ     args_pos+2
count_lines:    equ     current_entry+2
count_words:    equ     count_lines+2
count_bytes:    equ     count_words+2
total_lines:    equ     count_bytes+2
total_words:    equ     total_lines+2
total_bytes:    equ     total_words+2
numbuf:         equ     total_bytes+2
work:           equ     numbuf+8
word:           equ     work+130
pattern:        equ     word+64
dir_buffer:     equ     pattern+36
temp_files:     equ     dir_buffer+128
all_files:      equ     temp_files+MAX_TEMP*12
reader:         equ     all_files+MAX_ALL*13
stack_low:      equ     reader+R_SIZE
stack_top:      equ     stack_low+128
