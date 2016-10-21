; DF: the size and the free space of disks.
;
;     DF [d: ...]
;
; Without a drive, all the drives that CP/M has logged in. For each: the size in K, the
; K in use, the K free, and the directory entries in use and in all. A drive that CP/M has
; not logged in must be named, and has to be there: CP/M ends a program that selects a
; drive that does not exist.

BDOS:           equ     0005h
TAIL:           equ     0080h

        org     0100h
start:  ld      (orig_sp),sp
        ld      sp,stack_top
        call    main
        ld      sp,(orig_sp)
        ret

main:   call    args_init
        ld      c,25
        call    BDOS
        ld      (old_drive),a
        ld      hl,0
        ld      (drive_mask),hl
        ld      a,0
        ld      (words_seen),a
main_word:
        call    next_word
        jr      c,main_run
        ld      a,(word)
        cp      'A'
        jr      c,usage
        cp      'P'+1
        jr      nc,usage
        ld      a,(word+1)
        cp      ':'
        jr      nz,usage
        ld      a,(word+2)
        or      a
        jr      nz,usage
        ld      a,(word)
        sub     'A'
        call    drive_bit
        ld      hl,(drive_mask)
        ld      a,l
        or      c
        ld      l,a
        ld      a,h
        or      b
        ld      h,a
        ld      (drive_mask),hl
        ld      a,1
        ld      (words_seen),a
        jr      main_word
main_run:
        ld      a,(words_seen)
        or      a
        jr      nz,main_list
        ld      c,24
        call    BDOS
        ld      (drive_mask),hl
main_list:
        ld      de,msg_header
        call    print
        xor     a
        ld      (drive),a
list_next:
        ld      a,(drive)
        call    drive_bit
        ld      hl,(drive_mask)
        ld      a,l
        and     c
        ld      l,a
        ld      a,h
        and     b
        or      l
        call    nz,list_drive
        ld      hl,drive
        inc     (hl)
        ld      a,(hl)
        cp      16
        jr      c,list_next
        ld      a,(old_drive)
        ld      e,a
        ld      c,14
        jp      BDOS
usage:  ld      de,msg_usage
        jp      print

tool_option:
        scf
        ret

; BC = 1 shifted left by the drive A.
drive_bit:
        ld      bc,1
        or      a
        ret     z
drive_bit_next:
        sla     c
        rl      b
        dec     a
        jr      nz,drive_bit_next
        ret

; One line for the drive (drive).
list_drive:
        ld      a,(drive)
        call    disk_info
        ld      a,(drive)
        add     a,'A'
        ld      e,a
        call    put_char
        ld      e,':'
        call    put_char
        ld      e,' '
        call    put_char
        ld      hl,(disk_blocks)
        call    disk_kilobytes
        ld      (size_k),hl
        call    put_k
        ld      hl,(disk_blocks)
        ld      de,(disk_free)
        or      a
        sbc     hl,de
        call    disk_kilobytes
        call    put_k
        ld      hl,(disk_free)
        call    disk_kilobytes
        call    put_k
        call    count_entries
        ld      hl,(entries)
        call    put_number5
        ld      e,'/'
        call    put_char
        ld      hl,(disk_dir)
        call    put_number
        jp      print_crlf

put_k:
        call    put_number5
        ld      e,'K'
        call    put_char
        ld      e,' '
        jp      put_char

; The directory entries of the selected drive that are in use.
count_entries:
        ld      hl,0
        ld      (entries),hl
        ld      hl,pattern
        ld      de,pattern+1
        ld      bc,35
        ld      (hl),'?'
        ldir
        ld      de,pattern
        call    dir_first
count_next:
        jr      c,count_done
        ld      hl,(entries)
        inc     hl
        ld      (entries),hl
        call    dir_next
        jr      count_next
count_done:
        ret

        include "cpm_fcb.asm"
        include "cpm_args.asm"
        include "cpm_io.asm"
        include "decimal.asm"
        include "cpm_disk.asm"

msg_header:     defm "Drive    Size    Used    Free  Dir",13,10,'$'
msg_usage:      defm "Usage: DF [d: ...]",13,10,'$'
args:           defw 0

image_end:
old_drive:      equ     image_end
words_seen:     equ     old_drive+1
drive:          equ     words_seen+1
orig_sp:        equ     drive+1
args_pos:       equ     orig_sp+2
drive_mask:     equ     args_pos+2
size_k:         equ     drive_mask+2
entries:        equ     size_k+2
disk_shift:     equ     entries+2
disk_byte:      equ     disk_shift+1
disk_bits:      equ     disk_byte+1
disk_alloc:     equ     disk_bits+1
disk_blocks:    equ     disk_alloc+2
disk_free:      equ     disk_blocks+2
disk_dir:       equ     disk_free+2
numbuf:         equ     disk_dir+2
work:           equ     numbuf+8
word:           equ     work+130
pattern:        equ     word+64
dir_buffer:     equ     pattern+36
stack_low:      equ     dir_buffer+128
stack_top:      equ     stack_low+128
