; The size of a disk and its free space, from the BDOS (the allocation vector and the disk
; parameter block). The program defines disk_alloc, disk_blocks, disk_free, disk_shift,
; disk_dir and disk_byte, disk_bits (variables).

; A = the drive (0 is A:). The drive is selected. Gives disk_blocks (the blocks of the
; disk), disk_free (the blocks that are not in use), disk_shift (block size = 128 << it) and
; disk_dir (the directory entries).
disk_info:
        ld      e,a
        ld      c,14
        call    BDOS
        ld      c,27
        call    BDOS
        ld      (disk_alloc),hl
        ld      c,31
        call    BDOS
        push    hl
        pop     ix
        ld      c,(ix+5)
        ld      b,(ix+6)
        inc     bc
        ld      (disk_blocks),bc
        ld      e,(ix+7)
        ld      d,(ix+8)
        inc     de
        ld      (disk_dir),de
        ld      a,(ix+2)
        ld      (disk_shift),a
        ld      hl,(disk_alloc)
        ld      de,0
disk_next_byte:
        ld      a,b
        or      c
        jr      z,disk_counted
        ld      a,(hl)
        inc     hl
        ld      (disk_byte),a
        ld      a,8
        ld      (disk_bits),a
disk_next_bit:
        ld      a,b
        or      c
        jr      z,disk_counted
        ld      a,(disk_byte)
        add     a,a
        ld      (disk_byte),a
        jr      c,disk_bit_used
        inc     de
disk_bit_used:
        dec     bc
        ld      a,(disk_bits)
        dec     a
        ld      (disk_bits),a
        jr      nz,disk_next_bit
        jr      disk_next_byte
disk_counted:
        ld      (disk_free),de
        ret

; HL = blocks as K.
disk_kilobytes:
        ld      a,(disk_shift)
        sub     3
        ret     z
        ld      b,a
disk_scale:
        add     hl,hl
        djnz    disk_scale
        ret
