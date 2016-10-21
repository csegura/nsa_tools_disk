; The program runs on its own stack and registers. A planted breakpoint is RST 38h,
; which comes here through the jump at 0038h; the registers go to the nsd_ variables,
; and `resume` puts them back.
trap_entry:
        ld      (nsd_hl),hl
        pop     hl
        dec     hl
        ld      (nsd_pc),hl
        ld      (nsd_sp),sp
        ld      sp,nsd_stack
        push    af
        pop     hl
        ld      (nsd_af),hl
        ld      (nsd_bc),bc
        ld      (nsd_de),de
        ld      (nsd_ix),ix
        ld      (nsd_iy),iy
        ld      a,i
        ld      (nsd_i),a
        ex      af,af'
        push    af
        pop     hl
        ld      (nsd_af2),hl
        exx
        ld      (nsd_bc2),bc
        ld      (nsd_de2),de
        ld      (nsd_hl2),hl
        exx
        jp      trap_stop

; Give the program its registers and go on at nsd_pc. The return address goes below
; the stack pointer of the program, in the room that a push would use.
resume:
        ld      sp,(nsd_sp)
        ld      hl,(nsd_pc)
        push    hl
        ld      hl,(nsd_af2)
        push    hl
        pop     af
        ex      af,af'
        exx
        ld      bc,(nsd_bc2)
        ld      de,(nsd_de2)
        ld      hl,(nsd_hl2)
        exx
        ld      ix,(nsd_ix)
        ld      iy,(nsd_iy)
        ld      bc,(nsd_bc)
        ld      de,(nsd_de)
        ld      a,(nsd_i)
        ld      i,a
        ld      hl,(nsd_af)
        push    hl
        pop     af
        ld      hl,(nsd_hl)
        ret
