; Runs at 0100h. Checks that the resident part and its buffers fit under the BDOS and moves
; the resident part up.
loader: ld      a,(FCB1+1)
        cp      ' '
        jr      z,usage
        ld      a,(0007h)
        ld      h,a
        ld      l,0
        ld      de,nsd_bss_end
        or      a
        sbc     hl,de
        jr      c,no_room
        ld      hl,img_src
        ld      de,NSD_BASE
        ld      bc,res_end-NSD_BASE
        ldir
        jp      res_init

usage:  ld      de,ld_usage
        jr      ld_leave
no_room:
        ld      de,ld_no_room
ld_leave:
        ld      c,9
        call    BDOS
        jp      0

ld_usage:       defm "Usage: NSADB [d:]program [arguments]",13,10,'$'
ld_no_room:     defm "NSADB: not enough memory",13,10,'$'
