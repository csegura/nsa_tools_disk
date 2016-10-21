; RM: erase files.
;
;     RM [-f] [-u N] [d:]file ...
;
; The names may have * and ?. A read-only file is not erased unless -f is given (CP/M would
; end the program with an error). -u N works in the user area N. Each file that is erased
; is shown.

BDOS:           equ     0005h
TAIL:           equ     0080h
MAX_TEMP:       equ     64
MAX_ALL:        equ     64
MAX_WORDS:      equ     16
WORD_SIZE:      equ     24

        org     0100h
start:  ld      (orig_sp),sp
        ld      sp,stack_top
        ld      hl,flag_force
        ld      de,flag_force+1
        ld      bc,flags_end-flag_force-1
        ld      (hl),0
        ldir
        call    main
        ld      a,(old_user)
        call    set_user
        ld      sp,(orig_sp)
        ret

main:   call    get_user
        ld      (old_user),a
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
        ld      a,(word_count)
        cp      MAX_WORDS
        jr      nc,usage
        call    word_slot
        ex      de,hl
        ld      hl,word
        ld      bc,WORD_SIZE
        ldir
        ld      hl,word_count
        inc     (hl)
        jr      main_word
; The user area (-u) is known only now, wherever it was in the line: gather the names.
main_run:
        ld      a,(word_count)
        or      a
        jr      z,usage
        ld      b,a
        ld      c,0
gather_all:
        push    bc
        ld      a,c
        call    word_slot
        ld      de,word
        ld      bc,WORD_SIZE
        ldir
        call    gather_word
        pop     bc
        inc     c
        djnz    gather_all
        ld      a,(all_count)
        or      a
        jr      z,main_none
        jp      erase_all
main_none:
        ld      a,(missing)
        or      a
        ret     nz
usage:  ld      de,msg_usage
        jp      print

tool_option:
        cp      'F'
        jr      nz,option_user
        ld      a,1
        ld      (flag_force),a
        or      a
        ret
option_user:
        cp      'U'
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
        cp      16
        ccf
        ret     c
        ld      (user),a
        call    set_user
        or      a
        ret

; HL = the place of the word A of the list.
word_slot:
        ld      l,a
        ld      h,0
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,de
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,word_list
        add     hl,de
        ret

; Erase each gathered file.
erase_all:
        ld      a,(all_count)
        ld      b,a
        ld      hl,all_files
erase_next:
        push    bc
        push    hl
        ld      (current_entry),hl
        call    erase_one
        pop     hl
        ld      bc,13
        add     hl,bc
        pop     bc
        djnz    erase_next
        ret

; The file at current_entry.
erase_one:
        ld      hl,(current_entry)
        ld      de,fcb
        ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        ld      bc,11
        ldir
        ld      b,24
        xor     a
erase_zero:
        ld      (de),a
        inc     de
        djnz    erase_zero
        ld      hl,(current_entry)
        ld      de,12
        add     hl,de
        ld      a,(hl)
        and     1
        jr      z,erase_it
        ld      a,(flag_force)
        or      a
        jr      nz,erase_unprotect
        ld      hl,(current_entry)
        inc     hl
        call    put_file_name
        ld      hl,msg_readonly
        jp      put_text
erase_unprotect:
        ld      hl,fcb+9
        res     7,(hl)
        ld      de,fcb
        ld      c,30
        call    BDOS
erase_it:
        ld      a,'?'
        ld      (fcb+12),a
        ld      de,fcb
        ld      c,19
        call    BDOS
        inc     a
        ld      hl,msg_erased
        jr      nz,erase_report
        ld      hl,msg_not_erased
erase_report:
        push    hl
        ld      hl,(current_entry)
        inc     hl
        call    put_file_name
        pop     hl
        jp      put_text

        include "cpm_fcb.asm"
        include "cpm_args.asm"
        include "cpm_files.asm"
        include "cpm_io.asm"
        include "decimal.asm"

msg_usage:      defm "Usage: RM [-f] [-u N] [d:]file ...",13,10,'$'
msg_not_found:  defm ": not found",13,10,0
msg_readonly:   defm ": read-only (-f erases it)",13,10,0
msg_erased:     defm " erased",13,10,0
msg_not_erased: defm " was not erased",13,10,0
args:           defw 0

image_end:
flag_force:     equ     image_end
all_count:      equ     flag_force+1
missing:        equ     all_count+1
user:           equ     missing+1
word_count:     equ     user+1
flags_end:      equ     word_count+1
orig_sp:        equ     flags_end
args_pos:       equ     orig_sp+2
old_user:       equ     args_pos+2
current_entry:  equ     old_user+1
numbuf:         equ     current_entry+2
work:           equ     numbuf+8
word:           equ     work+130
pattern:        equ     word+64
fcb:            equ     pattern+36
word_list:      equ     fcb+36
dir_buffer:     equ     word_list+MAX_WORDS*WORD_SIZE
temp_files:     equ     dir_buffer+128
all_files:      equ     temp_files+MAX_TEMP*12
stack_low:      equ     all_files+MAX_ALL*13
stack_top:      equ     stack_low+128
