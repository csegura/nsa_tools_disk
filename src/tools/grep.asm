; GREP: print the lines of files that have a text.
;
;     GREP [-n] [-c] [-l] [-v] text [d:]file ...
;
;   -n  the line number before each line      -c  only the number of lines that match
;   -l  only the names of files that have it  -v  the lines that do not match
;
;   -r  look in all the user areas (each name is shown as u:NAME.EXT)
;
; The text is plain, not a pattern, except that ^ at its start means the start of a line
; and $ at its end means the end of a line. CP/M makes the command line capital letters
; before the program sees it, so the search ignores the case of the letters of the file
; as well. A text with blanks goes between quotes. With more than one file each line has
; the name of its file.

BDOS:           equ     0005h
TAIL:           equ     0080h
MAX_TEMP:       equ     40
MAX_ALL:        equ     64
LINE_SIZE:      equ     200

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
        jr      nz,main_plain
        ld      a,(word+1)
        or      a
        jr      z,main_plain
        call    parse_options
        jr      nc,main_word
        jr      usage
main_plain:
        ld      a,(have_needle)
        or      a
        jr      nz,main_file
        call    set_needle
        jr      main_word
main_file:
        ld      a,(flag_recursive)
        or      a
        jr      nz,main_all_users
        call    gather_word
        jr      main_word
; -r: the word is looked for in the user areas 0 to 15.
main_all_users:
        call    get_user
        ld      (home_user),a
        ld      a,(all_count)
        ld      (count_before),a
        ld      a,1
        ld      (gather_quiet),a
        xor     a
        ld      (scan_user),a
scan_next:
        ld      a,(scan_user)
        call    set_user
        call    gather_word
        ld      hl,scan_user
        inc     (hl)
        ld      a,(hl)
        cp      16
        jr      c,scan_next
        xor     a
        ld      (gather_quiet),a
        ld      a,(home_user)
        call    set_user
        ld      a,(all_count)
        ld      hl,count_before
        cp      (hl)
        jp      nz,main_word
        ld      hl,word
        call    put_text
        ld      hl,msg_not_found
        call    put_text
        ld      a,1
        ld      (missing),a
        jp      main_word
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
        ld      hl,flag_numbers
        cp      'N'
        jr      z,option_set
        ld      hl,flag_count
        cp      'C'
        jr      z,option_set
        ld      hl,flag_names
        cp      'L'
        jr      z,option_set
        ld      hl,flag_invert
        cp      'V'
        jr      z,option_set
        cp      'R'
        scf
        ret     nz
        ld      a,1
        ld      (flag_recursive),a
        ld      (show_user),a
        or      a
        ret
option_set:
        ld      (hl),1
        or      a
        ret

; The first word that is not an option is the text: it goes to `needle`, in capitals,
; without the ^ and $ that anchor it.
set_needle:
        ld      a,1
        ld      (have_needle),a
        ld      hl,word
        ld      a,(hl)
        cp      '^'
        jr      nz,needle_start
        ld      (anchor_start),a
        inc     hl
needle_start:
        ld      de,needle
        ld      b,0
needle_copy:
        ld      a,(hl)
        or      a
        jr      z,needle_end
        inc     hl
        call    to_upper
        ld      (de),a
        inc     de
        inc     b
        jr      needle_copy
needle_end:
        xor     a
        ld      (de),a
        ld      a,b
        or      a
        jr      z,needle_done
        dec     de
        ld      a,(de)
        cp      '$'
        jr      nz,needle_done
        ld      (anchor_end),a
        xor     a
        ld      (de),a
        dec     b
needle_done:
        ld      a,b
        ld      (needle_length),a
        ret

to_upper:
        cp      'a'
        ret     c
        cp      'z'+1
        ret     nc
        sub     20h
        ret

; The open file.
tool_file:
        ld      hl,0
        ld      (line_number),hl
        ld      (match_count),hl
grep_line:
        ld      ix,reader
        ld      de,line
        ld      b,LINE_SIZE
        call    rd_line
        jr      c,grep_end
        ld      hl,(line_number)
        inc     hl
        ld      (line_number),hl
        call    match_line
        ld      b,a
        ld      a,(flag_invert)
        xor     b
        and     1
        jr      z,grep_line
        ld      hl,(match_count)
        inc     hl
        ld      (match_count),hl
        ld      a,(flag_names)
        or      a
        jr      nz,grep_end
        ld      a,(flag_count)
        or      a
        jr      nz,grep_line
        call    print_prefix
        ld      hl,line
        call    put_text
        call    print_crlf
        jr      grep_line
grep_end:
        ld      a,(rd_cut)
        or      a
        jr      z,grep_not_cut
        xor     a
        ld      (rd_cut),a
        call    put_entry_name
        ld      hl,msg_cut
        call    put_text
grep_not_cut:
        ld      a,(flag_names)
        or      a
        jr      z,grep_counts
        ld      hl,(match_count)
        ld      a,h
        or      l
        ret     z
        call    put_entry_name
        jp      print_crlf
grep_counts:
        ld      a,(flag_count)
        or      a
        ret     z
        ld      a,(all_count)
        cp      2
        jr      c,grep_total
        call    put_entry_name
        ld      e,':'
        call    put_char
grep_total:
        ld      hl,(match_count)
        call    put_number
        jp      print_crlf

; The name of the file and the line number, as they are asked for, before a line.
print_prefix:
        ld      a,(all_count)
        cp      2
        jr      c,prefix_number
        call    put_entry_name
        ld      e,':'
        call    put_char
prefix_number:
        ld      a,(flag_numbers)
        or      a
        ret     z
        ld      hl,(line_number)
        call    put_number
        ld      e,':'
        jp      put_char

; A = 1 when the line has the text, else 0.
match_line:
        ld      a,(needle_length)
        or      a
        jr      nz,match_start
        ld      a,(anchor_start)
        ld      hl,anchor_end
        and     (hl)
        jr      z,match_all
        ld      a,(line)
        or      a
        ld      a,0
        ret     nz
        inc     a
        ret
match_all:
        ld      a,1
        ret
match_start:
        ld      hl,line
match_try:
        push    hl
        ld      de,needle
match_char:
        ld      a,(de)
        or      a
        jr      z,match_ended
        ld      b,a
        ld      a,(hl)
        or      a
        jr      z,match_fail
        call    to_upper
        cp      b
        jr      nz,match_fail
        inc     hl
        inc     de
        jr      match_char
match_ended:
        ld      a,(anchor_end)
        or      a
        jr      z,match_yes
        ld      a,(hl)
        or      a
        jr      nz,match_fail
match_yes:
        pop     hl
        ld      a,1
        ret
match_fail:
        pop     hl
        ld      a,(anchor_start)
        or      a
        jr      nz,match_no
        inc     hl
        ld      a,(hl)
        or      a
        jr      nz,match_try
match_no:
        xor     a
        ret

        include "cpm_fcb.asm"
        include "cpm_args.asm"
        include "cpm_files.asm"
        include "cpm_process.asm"
        include "cpm_io.asm"
        include "decimal.asm"

msg_usage:      defm "Usage: GREP [-n] [-c] [-l] [-v] [-r] text [d:]file ...",13,10,'$'
msg_cut:        defm ": lines longer than 199 characters were cut, a match after that is not found",13,10,0
msg_not_found:  defm ": not found",13,10,0
args:           defw 0

image_end:
flag_numbers:   equ     image_end
flag_count:     equ     flag_numbers+1
flag_names:     equ     flag_count+1
flag_invert:    equ     flag_names+1
flag_recursive: equ     flag_invert+1
count_before:   equ     flag_recursive+1
scan_user:      equ     count_before+1
have_needle:    equ     scan_user+1
anchor_start:   equ     have_needle+1
anchor_end:     equ     anchor_start+1
needle_length:  equ     anchor_end+1
all_count:      equ     needle_length+1
missing:        equ     all_count+1
flags_end:      equ     missing+1
orig_sp:        equ     flags_end
args_pos:       equ     orig_sp+2
current_entry:  equ     args_pos+2
line_number:    equ     current_entry+2
match_count:    equ     line_number+2
numbuf:         equ     match_count+2
work:           equ     numbuf+8
word:           equ     work+130
pattern:        equ     word+64
needle:         equ     pattern+36
line:           equ     needle+64
dir_buffer:     equ     line+LINE_SIZE+1
temp_files:     equ     dir_buffer+128
all_files:      equ     temp_files+MAX_TEMP*12
reader:         equ     all_files+MAX_ALL*13
stack_low:      equ     reader+R_SIZE
stack_top:      equ     stack_low+128
