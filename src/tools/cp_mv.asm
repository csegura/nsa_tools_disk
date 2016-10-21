; CP and MV: copy or move files, between drives and user areas. One source, built twice
; (MV is assembled with IS_MOVE set to 1).
;
;     CP [-f] [-u N] [-t N] [d:]file ... destination      CP [-f] -a [-u N] [-t N] destination
;     MV [-f] [-u N] [-t N] [d:]file ... destination
;
; With -a and only the destination, all the files of the user area (*.*) are copied.
; The destination is a drive (B:), to keep the names, or one file name when there is one
; file. The names may have * and ?. -u N reads from the user area N, -t N writes to the
; user area N; both are the current one otherwise. A file that is already there is not
; written over unless -f is given. A file keeps its read-only and system attributes. MV on
; one drive and one user area renames; otherwise it copies and then erases, and a source
; that is read-only is only erased with -f.

BDOS:           equ     0005h
TAIL:           equ     0080h
MAX_TEMP:       equ     255
MAX_ALL:        equ     255
MAX_WORDS:      equ     8
WORD_SIZE:      equ     24
RECORDS:        equ     64

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
        ld      (source_user),a
        ld      (target_user),a
        ld      c,25
        call    BDOS
        ld      (old_drive),a
        call    args_init
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
        ld      a,(word_count)
        cp      MAX_WORDS
        jr      nc,usage
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
        ex      de,hl
        ld      hl,word
        ld      bc,WORD_SIZE-1
        ldir
        xor     a
        ld      (de),a
        ld      hl,word_count
        inc     (hl)
        jr      main_word
main_run:
        ld      a,(flag_all)
        or      a
        jr      z,main_sources
        ld      a,(word_count)
        cp      1
        jr      nz,usage
        ld      hl,word_list
        ld      de,word_list+WORD_SIZE
        ld      bc,WORD_SIZE
        ldir
        ld      hl,text_all
        ld      de,word_list
        ld      bc,4
        ldir
        ld      a,2
        ld      (word_count),a
main_sources:
        ld      a,(word_count)
        cp      2
        jr      c,usage
        call    prepare
        jp      c,usage
        call    copy_all
        ret
usage:  ld      de,msg_usage
        jp      print

; -f, -a, -u N and -t N
tool_option:
        cp      'F'
        jr      nz,option_all
        ld      a,1
        ld      (flag_force),a
        or      a
        ret
option_all:
        cp      'A'
        jr      nz,option_user
        ld      a,1
        ld      (flag_all),a
        or      a
        ret
option_user:
        ld      hl,source_user
        cp      'U'
        jr      z,option_number
        ld      hl,target_user
        cp      'T'
        scf
        ret     nz
option_number:
        push    hl
        call    next_word
        pop     hl
        ret     c
        push    hl
        ld      hl,word
        call    parse_decimal
        pop     hl
        ret     c
        ld      a,d
        or      a
        scf
        ret     nz
        ld      a,e
        cp      16
        ccf
        ret     c
        ld      (hl),a
        or      a
        ret

; The words but the last are gathered (in the source user area); the last is the
; destination. Carry for a destination that cannot be.
prepare:
        ld      a,(source_user)
        call    set_user
        ld      a,(word_count)
        dec     a
        ld      (sources),a
        ld      b,a
        ld      c,0
prepare_gather:
        push    bc
        ld      a,c
        call    word_address
        ld      de,word
        ld      bc,WORD_SIZE
        ldir
        call    gather_word
        pop     bc
        inc     c
        djnz    prepare_gather
        ld      a,(sources)
        call    word_address
        ld      de,dest
        call    parse_fcb
        ld      hl,dest+1
        ld      a,(hl)
        ld      (dest_dir),a
        ld      b,11
prepare_wild:
        ld      a,(hl)
        cp      '?'
        scf
        ret     z
        inc     hl
        djnz    prepare_wild
        ld      a,(dest_dir)
        cp      ' '
        ld      a,1
        jr      z,prepare_names
        xor     a
prepare_names:
        ld      (dest_dir),a
        or      a
        jr      nz,prepare_ok
        ld      a,(all_count)
        cp      1
        scf
        ret     nz
prepare_ok:
        or      a
        ret

; HL = the word A of the list.
word_address:
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

copy_all:
        ld      a,(all_count)
        or      a
        jr      nz,copy_have
        ld      a,(missing)
        or      a
        ret     nz
        ld      de,msg_usage
        jp      print
copy_have:
        ld      b,a
        ld      hl,all_files
copy_next:
        push    bc
        push    hl
        ld      (current_entry),hl
        call    copy_one
        pop     hl
        ld      bc,13
        add     hl,bc
        pop     bc
        djnz    copy_next
        ret

; The names of the file at current_entry: src_fcb, dst_fcb (the destination) and tmp_fcb (a
; name in the same place that is written first, so that the destination is never touched
; until the copy has worked).
build_names:
        ld      hl,src_fcb
        ld      de,src_fcb+1
        ld      bc,35
        ld      (hl),0
        ldir
        call    build_destination
        ld      hl,src_fcb
        ld      de,tmp_fcb
        ld      hl,dst_fcb
        ld      bc,36
        ldir
        ld      hl,temp_name
        ld      de,tmp_fcb+1
        ld      bc,11
        ldir
        ld      hl,(current_entry)
        ld      a,(hl)
        ld      (src_fcb),a
        inc     hl
        ld      de,src_fcb+1
        ld      bc,11
        ldir
        ret

; dst_fcb: the drive and the name of the destination, the rest zero.
build_destination:
        ld      hl,dst_fcb
        ld      de,dst_fcb+1
        ld      bc,35
        ld      (hl),0
        ldir
        ld      a,(dest)
        ld      (dst_fcb),a
        ld      hl,dest+1
        ld      a,(dest_dir)
        or      a
        jr      z,build_dest
        ld      hl,(current_entry)
        inc     hl
build_dest:
        ld      de,dst_fcb+1
        ld      bc,11
        ldir
        ret

; The drive of an FCB: 0 is the current drive.
drive_of:
        or      a
        ret     nz
        ld      a,(old_drive)
        inc     a
        ret

copy_one:
        call    build_names
        ld      a,(src_fcb)
        call    drive_of
        ld      b,a
        ld      a,(dst_fcb)
        call    drive_of
        cp      b
        jr      nz,copy_different
        ld      a,(source_user)
        ld      hl,target_user
        cp      (hl)
        jr      nz,copy_different
        ld      hl,src_fcb+1
        ld      de,dst_fcb+1
        ld      b,11
copy_same_name:
        ld      a,(de)
        cp      (hl)
        jr      nz,copy_different
        inc     hl
        inc     de
        djnz    copy_same_name
        ld      hl,msg_same
        jp      report
copy_different:
        ld      a,(target_user)
        call    set_user
        xor     a
        ld      (dest_exists),a
        ld      de,dst_fcb
        ld      c,15
        call    BDOS
        inc     a
        jr      z,copy_new
        ld      a,(flag_force)
        or      a
        jr      nz,copy_will_replace
        ld      hl,msg_exists
        jp      report
copy_will_replace:
        ld      a,1
        ld      (dest_exists),a
copy_new:
        ld      a,IS_MOVE
        or      a
        jr      z,copy_start
        call    same_place
        jp      z,rename_it
copy_start:
        ld      a,(source_user)
        call    set_user
        ld      de,src_fcb
        ld      c,15
        call    BDOS
        inc     a
        jr      nz,copy_source_open
        ld      hl,msg_no_source
        jp      report
copy_source_open:
        xor     a
        ld      (src_fcb+32),a
        ld      a,(target_user)
        call    set_user
        ld      de,tmp_fcb
        ld      c,19
        call    BDOS
        ld      de,tmp_fcb
        ld      c,22
        call    BDOS
        inc     a
        jr      nz,copy_loop
        ld      hl,msg_directory_full
        jp      report
copy_loop:
        ld      a,(source_user)
        call    set_user
        ld      hl,copy_buffer
        ld      b,0
copy_read:
        push    hl
        push    bc
        ex      de,hl
        ld      c,26
        call    BDOS
        ld      de,src_fcb
        ld      c,20
        call    BDOS
        pop     bc
        pop     hl
        or      a
        jr      nz,copy_read_done
        ld      de,128
        add     hl,de
        inc     b
        ld      a,b
        cp      RECORDS
        jr      nz,copy_read
        xor     a
copy_read_done:
        ld      (read_status),a
        ld      a,b
        ld      (record_count),a
        or      a
        jr      z,copy_close
        ld      a,(target_user)
        call    set_user
        ld      hl,copy_buffer
        ld      a,(record_count)
        ld      b,a
copy_write:
        push    hl
        push    bc
        ex      de,hl
        ld      c,26
        call    BDOS
        ld      de,tmp_fcb
        ld      c,21
        call    BDOS
        pop     bc
        pop     hl
        or      a
        jr      nz,copy_write_failed
        ld      de,128
        add     hl,de
        djnz    copy_write
        ld      a,(read_status)
        or      a
        jr      z,copy_loop
copy_close:
        ld      a,(read_status)
        cp      2
        jr      c,copy_finish
        ld      hl,msg_read_error
        jr      copy_abandon
copy_write_failed:
        ld      hl,msg_disk_full
; The copy did not work: the temporary file goes, and the destination was not touched.
copy_abandon:
        push    hl
        ld      a,(target_user)
        call    set_user
        ld      de,tmp_fcb
        ld      c,16
        call    BDOS
        ld      de,tmp_fcb
        ld      c,19
        call    BDOS
        pop     hl
        jp      report
copy_finish:
        ld      a,(target_user)
        call    set_user
        ld      de,tmp_fcb
        ld      c,16
        call    BDOS
        inc     a
        jr      nz,copy_replace
        ld      hl,msg_disk_full
        jr      copy_abandon
; The copy is complete: only now is the old destination, if it is there, erased, and the
; temporary file takes its name.
copy_replace:
        ld      a,(dest_exists)
        or      a
        call    nz,erase_destination
        call    rename_temporary
        jr      nz,copy_renamed
        ld      hl,msg_not_renamed
        jr      copy_abandon
copy_renamed:
        call    set_destination_attributes
        ld      a,IS_MOVE
        or      a
        jr      z,copy_done
        call    erase_source
        ret     nz
copy_done:
        ld      hl,msg_copied
        ld      a,IS_MOVE
        or      a
        jp      z,report
        ld      hl,msg_moved
        jp      report

; Erase the old file of the destination, read-only or not.
erase_destination:
        call    build_destination
        ld      de,dst_fcb
        ld      c,30
        call    BDOS
        ld      a,'?'
        ld      (dst_fcb+12),a
        ld      de,dst_fcb
        ld      c,19
        jp      BDOS

; Rename the temporary file to the name of the destination. NZ when it worked.
rename_temporary:
        call    build_destination
        ld      hl,tmp_fcb
        ld      de,rename_fcb
        ld      bc,16
        ldir
        ld      hl,dst_fcb+1
        ld      de,rename_fcb+17
        ld      bc,11
        ldir
        ld      de,rename_fcb
        ld      c,23
        call    BDOS
        inc     a
        ret

; The read-only and system attributes of the source go to the destination.
set_destination_attributes:
        call    build_destination
        ld      hl,(current_entry)
        ld      bc,12
        add     hl,bc
        ld      a,(hl)
        ld      hl,dst_fcb+9
        bit     0,a
        jr      z,attr_system
        set     7,(hl)
attr_system:
        inc     hl
        bit     1,a
        jr      z,attr_set
        set     7,(hl)
attr_set:
        ld      de,dst_fcb
        ld      c,30
        jp      BDOS

; Erase the source after a move. NZ when it is read-only and was left.
erase_source:
        ld      a,(source_user)
        call    set_user
        ld      hl,(current_entry)
        ld      bc,12
        add     hl,bc
        ld      a,(hl)
        and     1
        jr      z,erase_now
        ld      a,(flag_force)
        or      a
        jr      nz,erase_unprotect
        ld      hl,msg_left
        call    report
        or      1
        ret
erase_unprotect:
        ld      de,src_fcb
        ld      hl,src_fcb+9
        res     7,(hl)
        ld      c,30
        call    BDOS
erase_now:
        ld      a,'?'
        ld      (src_fcb+12),a
        ld      de,src_fcb
        ld      c,19
        call    BDOS
        xor     a
        ret

; Z when the source and the destination are on the same drive and user.
same_place:
        ld      a,(src_fcb)
        call    drive_of
        ld      b,a
        ld      a,(dst_fcb)
        call    drive_of
        cp      b
        ret     nz
        ld      a,(source_user)
        ld      hl,target_user
        cp      (hl)
        ret

; A move on one drive and user: the BDOS renames the file (the destination is erased first
; if there is one and -f was given).
rename_it:
        ld      a,(dest_exists)
        or      a
        call    nz,erase_destination
        ld      a,(source_user)
        call    set_user
        ld      hl,src_fcb
        ld      de,rename_fcb
        ld      bc,16
        ldir
        call    build_destination
        ld      hl,dst_fcb+1
        ld      de,rename_fcb+17
        ld      bc,11
        ldir
        ld      de,rename_fcb
        ld      c,23
        call    BDOS
        inc     a
        jr      nz,rename_done
        ld      hl,msg_no_source
        jp      report
rename_done:
        call    set_destination_attributes
        ld      hl,msg_moved
        jp      report

; The name of the file, and the message at HL.
report:
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

msg_usage:      defm "Usage: CP/MV [-f] [-a] [-u N] [-t N] [d:]file ... destination",13,10,'$'
msg_not_found:  defm ": not found",13,10,0
msg_copied:     defm " copied",13,10,0
msg_moved:      defm " moved",13,10,0
msg_left:       defm " copied, the source is read-only and was left (-f)",13,10,0
msg_same:       defm " is the destination: not copied",13,10,0
msg_exists:     defm ": the destination is there (-f replaces it)",13,10,0
msg_no_source:  defm ": cannot be opened",13,10,0
msg_not_renamed: defm ": the copy could not be given its name",13,10,0
msg_directory_full: defm ": the directory of the destination is full",13,10,0
msg_disk_full:  defm ": the disk of the destination is full",13,10,0
msg_read_error: defm ": read error",13,10,0
temp_name:      defm "CPTEMP  $$$"
text_all:       defm "*.*",0
args:           defw 0

image_end:
flag_force:     equ     image_end
flag_all:       equ     flag_force+1
word_count:     equ     flag_all+1
all_count:      equ     word_count+1
missing:        equ     all_count+1
sources:        equ     missing+1
dest_dir:       equ     sources+1
read_status:    equ     dest_dir+1
record_count:   equ     read_status+1
dest_exists:    equ     record_count+1
flags_end:      equ     dest_exists+1
orig_sp:        equ     flags_end
args_pos:       equ     orig_sp+2
old_user:       equ     args_pos+2
old_drive:      equ     old_user+1
source_user:    equ     old_drive+1
target_user:    equ     source_user+1
current_entry:  equ     target_user+1
numbuf:         equ     current_entry+2
work:           equ     numbuf+8
word:           equ     work+130
pattern:        equ     word+64
dest:           equ     pattern+36
src_fcb:        equ     dest+36
dst_fcb:        equ     src_fcb+36
tmp_fcb:        equ     dst_fcb+36
rename_fcb:     equ     tmp_fcb+36
word_list:      equ     rename_fcb+36
dir_buffer:     equ     word_list+MAX_WORDS*WORD_SIZE
temp_files:     equ     dir_buffer+128
all_files:      equ     temp_files+MAX_TEMP*12
copy_buffer:    equ     all_files+MAX_ALL*13
stack_low:      equ     copy_buffer+RECORDS*128
stack_top:      equ     stack_low+128
