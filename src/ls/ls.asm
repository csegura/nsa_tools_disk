; LS: list the files of a CP/M 2.2 disk.
;
;     LS [-l] [-a] [-1] [-s] [d:][pattern]
;
;   -l  one file per line with the size in K and the attributes (R read-only, S system)
;   -a  the files of all user areas (the user number is shown)
;   -1  one name per line
;   -s  largest first (it reads the size of every file, as -l does)
;
; The pattern has the usual * and ? and the default is all the files. The names are
; sorted. The last line says how many files there are and how much room the disk has.
; Only the BDOS console is used, so it works on any CP/M system.

BDOS:           equ     0005h
TAIL:           equ     0080h
MAX_FILES:      equ     255
ENTRY_SIZE:     equ     16              ; user, name and type (11), attributes, records (2), spare
E_ATTR:         equ     12
E_RECORDS:      equ     13
A_READONLY:     equ     1
A_SYSTEM:       equ     2
COLUMN_WIDTH:   equ     13
COLUMNS:        equ     6

        org     0100h
start:  ld      (orig_sp),sp
        ld      sp,stack_top
        ld      hl,opt_long
        ld      de,opt_long+1
        ld      bc,sort_index-opt_long-1
        ld      (hl),0
        ldir
        call    main
        ld      sp,(orig_sp)
        ret

main:   call    parse_arguments
        jr      c,usage
        call    prepare_disk
        call    scan_directory
        ld      a,(opt_long)
        ld      hl,opt_size
        or      (hl)
        call    nz,read_sizes
        call    sort_files
        call    print_files
        call    print_summary
        jp      restore_disk

usage:  ld      de,msg_usage
        jp      print

; ---------- the command line ----------
; Options start with -, the one other word is the pattern. Carry for a mistake.
parse_arguments:
        ld      a,(TAIL)
        and     07Fh
        ld      c,a
        ld      b,0
        ld      hl,TAIL+1
        ld      de,work
        or      a
        jr      z,args_copied
        ldir
args_copied:
        xor     a
        ld      (de),a
        ld      (have_pattern),a
        ld      hl,work
args_next:
        call    skip_blanks
        ld      a,(hl)
        or      a
        jr      z,args_done
        cp      '-'
        jr      z,args_option
        ld      a,(have_pattern)
        or      a
        scf
        ret     nz
        inc     a
        ld      (have_pattern),a
        ld      de,pattern
        call    parse_fcb
        push    hl
        call    default_extension
        pop     hl
        jr      args_next
args_option:
        inc     hl
option_letter:
        ld      a,(hl)
        or      a
        jr      z,args_done
        cp      ' '
        jr      z,args_next
        inc     hl
        cp      'a'
        jr      c,option_upper
        sub     20h
option_upper:
        ld      de,opt_long
        cp      'L'
        jr      z,option_set
        ld      de,opt_all
        cp      'A'
        jr      z,option_set
        ld      de,opt_one
        cp      '1'
        jr      z,option_set
        ld      de,opt_size
        cp      'S'
        jr      z,option_set
        scf
        ret
option_set:
        ld      a,1
        ld      (de),a
        jr      option_letter
args_done:
        ld      a,(have_pattern)
        or      a
        jr      nz,args_checked
        ld      hl,pattern
        ld      de,pattern+1
        ld      bc,35
        ld      (hl),0
        ldir
        ld      hl,pattern+1
        ld      de,pattern+2
        ld      bc,10
        ld      (hl),'?'
        ldir
args_checked:
        or      a
        ret

; A name without a type, as in LS V*, takes all the types, and no name (LS B:) is all
; the names.
default_extension:
        ld      hl,pattern+1
        ld      b,8
name_blank:
        ld      a,(hl)
        cp      ' '
        jr      nz,name_given
        inc     hl
        djnz    name_blank
        ld      hl,pattern+1
        ld      de,pattern+2
        ld      bc,7
        ld      (hl),'?'
        ldir
name_given:
        ld      hl,pattern+9
        ld      b,3
extension_blank:
        ld      a,(hl)
        cp      ' '
        ret     nz
        inc     hl
        djnz    extension_blank
        ld      hl,pattern+9
        ld      (hl),'?'
        inc     hl
        ld      (hl),'?'
        inc     hl
        ld      (hl),'?'
        ret

; ---------- the disk ----------
; Select the drive of the pattern; the search uses the current one. The drive and the user
; that were current are put back at the end.
prepare_disk:
        ld      c,25
        call    BDOS
        ld      (old_drive),a
        ld      e,0FFh
        ld      c,32
        call    BDOS
        ld      (old_user),a
        ld      a,(pattern)
        or      a
        jr      z,drive_selected
        dec     a
        ld      e,a
        ld      c,14
        call    BDOS
drive_selected:
        ld      a,'?'
        ld      (pattern+12),a
        xor     a
        ld      (pattern),a
        ld      a,(opt_all)
        or      a
        ret     z
        ld      a,'?'
        ld      (pattern),a
        ret

restore_disk:
        ld      a,(old_drive)
        ld      e,a
        ld      c,14
        call    BDOS
        ld      a,(old_user)
        ld      e,a
        ld      c,32
        jp      BDOS

; ---------- the directory ----------
scan_directory:
        ld      de,dir_buffer
        ld      c,26
        call    BDOS
        ld      de,pattern
        ld      c,17
        call    BDOS
scan_entry:
        cp      0FFh
        ret     z
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,dir_buffer
        add     hl,de
        call    add_entry
        ld      de,pattern
        ld      c,18
        call    BDOS
        jr      scan_entry

; HL = a directory entry. The file is added to the table unless it is there (one entry
; for each extent) or it is erased.
add_entry:
        ld      a,(hl)
        cp      0E5h
        ret     z
        ld      (new_entry),hl
        ld      a,(opt_all)
        or      a
        jr      z,add_accepted
        call    name_matches
        ret     nz
add_accepted:
        ld      hl,(new_entry)
        ld      de,entry
        ld      (de),a
        inc     de
        inc     hl
        ld      b,11
copy_name:
        ld      a,(hl)
        and     07Fh
        ld      (de),a
        inc     de
        inc     hl
        djnz    copy_name
        ld      hl,(new_entry)
        ld      de,9
        add     hl,de
        ld      a,0
        bit     7,(hl)
        jr      z,not_readonly
        ld      a,A_READONLY
not_readonly:
        inc     hl
        bit     7,(hl)
        jr      z,not_system
        or      A_SYSTEM
not_system:
        ld      (entry+E_ATTR),a
        ld      hl,files
        ld      a,(count)
        or      a
        jr      z,append
        ld      b,a
find_entry:
        push    hl
        push    bc
        ld      de,entry
        ld      b,12
compare_entry:
        ld      a,(de)
        cp      (hl)
        jr      nz,entry_differs
        inc     hl
        inc     de
        djnz    compare_entry
        pop     bc
        pop     hl
        ret
entry_differs:
        pop     bc
        pop     hl
        ld      de,ENTRY_SIZE
        add     hl,de
        djnz    find_entry
append:
        ld      a,(count)
        cp      MAX_FILES
        jr      c,append_room
        ld      a,1
        ld      (too_many),a
        ret
append_room:
        ex      de,hl
        ld      hl,entry
        ld      bc,ENTRY_SIZE
        ldir
        ld      hl,count
        inc     (hl)
        ret

; Z when the name and type of the directory entry at HL are those of the pattern. The BDOS
; does not look at the name when the drive byte is ? (all the user areas), so it is done here.
name_matches:
        inc     hl
        ld      de,pattern+1
        ld      b,11
name_matches_next:
        ld      a,(de)
        cp      '?'
        jr      z,name_matches_skip
        ld      c,a
        ld      a,(hl)
        and     7Fh
        cp      c
        ret     nz
name_matches_skip:
        inc     hl
        inc     de
        djnz    name_matches_next
        xor     a
        ret

; The size of each file in records, with BDOS function 35 in the user area of the file.
read_sizes:
        ld      a,(count)
        or      a
        ret     z
        ld      b,a
        ld      ix,files
size_next:
        push    bc
        ld      e,(ix+0)
        ld      c,32
        call    BDOS
        ld      hl,size_fcb
        ld      (hl),0
        inc     hl
        push    ix
        pop     de
        inc     de
        ex      de,hl
        ld      bc,11
        ldir
        ld      hl,size_fcb+12
        ld      b,24
        xor     a
size_clear:
        ld      (hl),a
        inc     hl
        djnz    size_clear
        ld      de,size_fcb
        ld      c,35
        call    BDOS
        ld      hl,(size_fcb+33)
        ld      (ix+E_RECORDS),l
        ld      (ix+E_RECORDS+1),h
        ld      de,ENTRY_SIZE
        add     ix,de
        pop     bc
        djnz    size_next
        ld      a,(old_user)
        ld      e,a
        ld      c,32
        jp      BDOS

; ---------- sorting ----------
; Insertion sort of the table: by name (and user), or by size with the largest first.
sort_files:
        ld      a,(count)
        cp      2
        ret     c
        ld      a,1
        ld      (sort_index),a
sort_outer:
        ld      a,(sort_index)
        call    entry_address
        ld      de,entry
        ld      bc,ENTRY_SIZE
        ldir
        ld      a,(sort_index)
        ld      (sort_pos),a
sort_inner:
        ld      a,(sort_pos)
        or      a
        jr      z,sort_place
        dec     a
        call    entry_address
        call    compare_new
        jr      nc,sort_place
        ld      a,(sort_pos)
        dec     a
        call    entry_address
        ld      de,ENTRY_SIZE
        push    hl
        add     hl,de
        ex      de,hl
        pop     hl
        ld      bc,ENTRY_SIZE
        ldir
        ld      hl,sort_pos
        dec     (hl)
        jr      sort_inner
sort_place:
        ld      a,(sort_pos)
        call    entry_address
        ex      de,hl
        ld      hl,entry
        ld      bc,ENTRY_SIZE
        ldir
        ld      hl,sort_index
        inc     (hl)
        ld      a,(count)
        cp      (hl)
        jr      nz,sort_outer
        ret

; HL = the entry A of the table.
entry_address:
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,files
        add     hl,de
        ret

; Carry when the entry that is being placed (`entry`) goes before the one at HL.
compare_new:
        ld      a,(opt_size)
        or      a
        jr      z,compare_names
        push    hl
        ld      de,E_RECORDS
        add     hl,de
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        ld      hl,(entry+E_RECORDS)
        or      a
        sbc     hl,bc
        pop     hl
        jr      z,compare_names
        ccf
        ret
compare_names:
        ld      de,entry+1
        push    hl
        inc     hl
        ld      b,11
compare_byte:
        ld      a,(de)
        cp      (hl)
        jr      nz,compare_done
        inc     hl
        inc     de
        djnz    compare_byte
        pop     hl
        ld      a,(entry)
        cp      (hl)
        ret
compare_done:
        pop     hl
        ret

; ---------- output ----------
print_files:
        ld      a,(count)
        or      a
        ret     z
        ld      b,a
        ld      hl,files
        xor     a
        ld      (column),a
print_next:
        push    bc
        push    hl
        call    print_entry
        pop     hl
        ld      de,ENTRY_SIZE
        add     hl,de
        pop     bc
        djnz    print_next
        ld      a,(column)
        or      a
        ret     z
        xor     a
        ld      (column),a
        jp      print_crlf

; HL = an entry: one line, or one column of a line.
print_entry:
        ld      (current),hl
        ld      de,line
        ld      a,(opt_all)
        or      a
        jr      z,entry_name
        ld      a,(hl)
        ld      l,a
        ld      h,0
        call    emit_number
        ld      a,':'
        call    emit_char
entry_name:
        ld      hl,(current)
        inc     hl
        ld      b,8
        call    emit_name_part
        ld      hl,(current)
        ld      bc,9
        add     hl,bc
        ld      a,(hl)
        cp      ' '
        jr      z,name_done
        ld      a,'.'
        call    emit_char
        ld      hl,(current)
        ld      bc,9
        add     hl,bc
        ld      b,3
        call    emit_name_part
name_done:
        ld      a,(opt_long)
        ld      hl,opt_size
        or      (hl)
        jr      nz,print_long
        ld      a,(opt_one)
        or      a
        jr      nz,end_line
        ld      a,COLUMN_WIDTH
        ld      b,COLUMNS
        ld      hl,opt_all
        bit     0,(hl)
        jr      z,column_pad
        ld      a,COLUMN_WIDTH+3
        ld      b,COLUMNS-1
column_pad:
        ld      (columns),a
        ld      a,b
        ld      (columns+1),a
        ld      a,(columns)
        call    emit_pad
        ld      a,'$'
        ld      (de),a
        ld      de,line
        call    print
        ld      a,(column)
        inc     a
        ld      hl,columns+1
        cp      (hl)
        jr      nz,column_next
        xor     a
        ld      (column),a
        jp      print_crlf
column_next:
        ld      (column),a
        ret

print_long:
        ld      a,COLUMN_WIDTH+3
        call    emit_pad
        ld      hl,(current)
        ld      bc,E_RECORDS
        add     hl,bc
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        ld      h,b
        ld      l,c
        call    records_to_k
        call    emit_decimal5
        ld      a,'K'
        call    emit_char
        ld      a,' '
        call    emit_char
        call    emit_char
        ld      hl,(current)
        ld      bc,E_ATTR
        add     hl,bc
        ld      b,(hl)
        ld      a,'-'
        bit     0,b
        jr      z,long_readonly
        ld      a,'R'
long_readonly:
        call    emit_char
        ld      a,'-'
        bit     1,b
        jr      z,long_system
        ld      a,'S'
long_system:
        call    emit_char
end_line:
        ld      a,13
        call    emit_char
        ld      a,10
        call    emit_char
        ld      a,'$'
        ld      (de),a
        ld      de,line
        jp      print

; HL = records, as K rounded up.
records_to_k:
        ld      bc,7
        add     hl,bc
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        ret

; The B characters at HL without the blanks at the end, to DE.
emit_name_part:
        push    hl
        ld      c,b
        ld      b,0
        add     hl,bc
        ld      b,c
trim_name:
        dec     hl
        ld      a,(hl)
        cp      ' '
        jr      nz,trimmed
        djnz    trim_name
trimmed:
        pop     hl
        ld      a,b
        or      a
        ret     z
copy_part:
        ld      a,(hl)
        inc     hl
        ld      (de),a
        inc     de
        djnz    copy_part
        ret

emit_char:
        ld      (de),a
        inc     de
        ret

; Blanks up to A characters in `line`.
emit_pad:
        ld      c,a
emit_pad_next:
        ld      hl,line
        ld      a,e
        sub     l
        cp      c
        ret     nc
        ld      a,' '
        ld      (de),a
        inc     de
        jr      emit_pad_next

; Copy the text at HL up to a zero to DE.
emit_text:
        ld      a,(hl)
        inc     hl
        or      a
        ret     z
        ld      (de),a
        inc     de
        jr      emit_text

print:  ld      c,9
        jp      BDOS

print_crlf:
        ld      de,msg_crlf
        jr      print

; "N files, SSSK used, FFFK free", and a note when the table was full.
print_summary:
        ld      a,(column)
        or      a
        call    nz,print_crlf
        ld      de,line
        ld      a,(count)
        ld      l,a
        ld      h,0
        call    emit_number
        ld      hl,msg_files
        call    emit_text
        ld      a,(opt_long)
        ld      hl,opt_size
        or      (hl)
        jr      z,summary_free
        push    de
        call    total_records
        pop     de
        call    records_to_k
        call    emit_number
        ld      hl,msg_used
        call    emit_text
summary_free:
        push    de
        call    free_kilobytes
        pop     de
        call    emit_number
        ld      hl,msg_free
        call    emit_text
        ld      a,(too_many)
        or      a
        jr      z,summary_end
        ld      hl,msg_many
        call    emit_text
summary_end:
        ld      a,13
        call    emit_char
        ld      a,10
        call    emit_char
        ld      a,'$'
        ld      (de),a
        ld      de,line
        jp      print

; HL = the records of all the files.
total_records:
        ld      hl,0
        ld      a,(count)
        or      a
        ret     z
        ld      b,a
        ld      ix,files
        ld      de,ENTRY_SIZE
total_next:
        push    de
        ld      e,(ix+E_RECORDS)
        ld      d,(ix+E_RECORDS+1)
        add     hl,de
        pop     de
        add     ix,de
        djnz    total_next
        ret

; HL = the free space of the selected disk in K: the blocks that the allocation vector of
; the BDOS does not have in use, times the size of a block.
free_kilobytes:
        ld      c,25
        call    BDOS
        call    disk_info
        ld      hl,(disk_free)
        jp      disk_kilobytes

        include "cpm_fcb.asm"
        include "decimal.asm"
        include "cpm_disk.asm"

msg_usage:      defm "Usage: LS [-l] [-a] [-1] [-s] [d:][pattern]",13,10,'$'
msg_crlf:       defm 13,10,'$'
msg_files:      defm " files, ",0
msg_used:       defm "K used, ",0
msg_free:       defm "K free",0
msg_many:       defm " (more files than the table holds)",0

args:           defw 0
image_end:
orig_sp:        equ     image_end
old_drive:      equ     orig_sp+2
old_user:       equ     old_drive+1
opt_long:       equ     old_user+1
opt_all:        equ     opt_long+1
opt_one:        equ     opt_all+1
opt_size:       equ     opt_one+1
have_pattern:   equ     opt_size+1
too_many:       equ     have_pattern+1
count:          equ     too_many+1
column:         equ     count+1
columns:        equ     column+1
sort_index:     equ     columns+2
sort_pos:       equ     sort_index+1
disk_shift:     equ     sort_pos+1
disk_byte:      equ     disk_shift+1
disk_bits:      equ     disk_byte+1
disk_alloc:     equ     disk_bits+1
disk_blocks:    equ     disk_alloc+2
disk_free:      equ     disk_blocks+2
disk_dir:       equ     disk_free+2
new_entry:      equ     disk_dir+2
current:        equ     new_entry+2
pattern:        equ     current+2
size_fcb:       equ     pattern+36
entry:          equ     size_fcb+36
numbuf:         equ     entry+ENTRY_SIZE
work:           equ     numbuf+8
line:           equ     work+130
dir_buffer:     equ     line+96
files:          equ     dir_buffer+128
stack_low:      equ     files+MAX_FILES*ENTRY_SIZE
stack_top:      equ     stack_low+128
