; The resident part. The BDOS hook must be the first thing: its address is what the
; program reads at 0006h.
        include "nsadb_output.asm"
bdos_orig:      equ     bdos_next+1             ; The jump of the hook is patched

res_init:
        ld      sp,nsd_stack
        call    read_command_line
        call    load_program
        call    install_hooks
        call    start_context
        call    dbg_load
        call    screen_init
        jr      nc,screen_ready
        call    remove_hooks
        ld      de,msg_no_screen
        jp      fail
screen_ready:
        jp      ui_start

; Split the command line into the program name (parsed into nsd_prog_fcb) and the
; arguments, and give the program its own tail and FCBs as the CCP would.
read_command_line:
        ld      a,(TAIL)
        and     07Fh
        ld      c,a
        ld      b,0
        ld      hl,TAIL+1
        ld      de,nsd_work
        or      a
        jr      z,tail_copied
        ldir
tail_copied:
        xor     a
        ld      (de),a
        ld      hl,nsd_work
        ld      de,nsd_prog_fcb
        call    parse_fcb
        ld      (args),hl
        ld      a,(nsd_prog_fcb+9)
        cp      ' '
        jr      nz,have_extension
        ld      hl,nsd_prog_fcb+9
        ld      (hl),'C'
        inc     hl
        ld      (hl),'O'
        inc     hl
        ld      (hl),'M'
have_extension:
        ld      hl,(args)
        call    skip_blanks
        ld      (args),hl
        call    make_tail
        ld      hl,(args)
        ld      de,FCB1
        call    parse_fcb
        xor     a
        ld      (FCB1+32),a
        ld      de,FCB2
        jp      parse_fcb

; Read the program at NSD_PROG. Leaves through the CP/M prompt when it cannot.
load_program:
        ld      de,nsd_prog_fcb
        ld      c,35
        call    BDOS
        ld      de,nsd_prog_fcb
        ld      c,15
        call    BDOS
        inc     a
        ld      de,msg_not_found
        jp      z,fail
        xor     a
        ld      (nsd_prog_fcb+32),a
        ld      hl,(NSD_BASE-NSD_PROG)/128
        ld      de,(nsd_prog_fcb+33)
        or      a
        sbc     hl,de
        ld      de,msg_too_large
        jp      c,fail
        ld      hl,NSD_PROG
load_record:
        push    hl
        ex      de,hl
        ld      c,26
        call    BDOS
        ld      de,nsd_prog_fcb
        ld      c,20
        call    BDOS
        pop     hl
        or      a
        jr      z,load_next
        cp      1
        ld      de,msg_read_error
        jp      nz,fail
        jr      load_done
load_next:
        ld      de,128
        add     hl,de
        jr      load_record
load_done:
        ld      de,TAIL
        ld      c,26
        jp      BDOS

; Make the program see less memory, and catch its warm boot.
install_hooks:
        ld      hl,(0001h)
        ld      a,(hl)
        cp      0C3h
        ld      de,msg_bios
        jp      nz,fail
        ld      hl,(0006h)
        ld      (bdos_orig),hl
        ld      hl,NSD_BASE
        ld      (0006h),hl
        ld      hl,(0001h)
        ld      (wboot_entry),hl
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (wboot_orig),de
        dec     hl
        ld      de,program_ended
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ld      hl,0038h
        ld      de,nsd_rst_save
        ld      bc,3
        ldir
        ld      a,0C3h
        ld      (0038h),a
        ld      hl,trap_entry
        ld      (0039h),hl
        ret

; The program leaves through a warm boot: JP 0, RET, or BDOS function 0.
program_ended:
        ld      sp,nsd_stack
        ld      hl,msg_ended
        ld      (ui_msg),hl
        call    ui_draw
        call    read_key
        jp      key_quit

remove_hooks:
        ld      hl,nsd_rst_save
        ld      de,0038h
        ld      bc,3
        ldir
        ld      hl,(bdos_orig)
        ld      (0006h),hl
        ld      hl,(wboot_entry)
        inc     hl
        ld      de,(wboot_orig)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ret

fail:   ld      c,9
        call    BDOS
        jp      0

; The program starts as the CCP would start it: the stack at the top of its memory
; with a return to the warm boot, and the drive and user in C.
start_context:
        ld      hl,TAIL
        ld      (nsd_dma),hl
        ld      hl,NSD_BASE-2
        ld      (nsd_sp),hl
        ld      hl,0
        ld      (NSD_BASE-2),hl
        ld      hl,NSD_PROG
        ld      (nsd_pc),hl
        ld      a,(0004h)
        ld      l,a
        ld      h,0
        ld      (nsd_bc),hl
        ld      l,h
        ld      (nsd_af),hl
        ld      (nsd_de),hl
        ld      (nsd_hl),hl
        ld      (nsd_ix),hl
        ld      (nsd_iy),hl
        ld      (nsd_af2),hl
        ld      (nsd_bc2),hl
        ld      (nsd_de2),hl
        ld      (nsd_hl2),hl
        xor     a
        ld      (nsd_i),a
        ld      (nsd_bp_n),a
        ld      (nsd_plant_n),a
        ld      (nsd_go_after),a
        ret

        include "cpm_fcb.asm"
        include "nsadb_context.asm"
        include "nsadb_length.asm"
        include "nsadb_disasm.asm"
        include "nsadb_engine.asm"
        include "nsadb_screen.asm"
        include "nsadb_dbg.asm"
        include "nsadb_source.asm"
        include "nsadb_ui.asm"

msg_no_screen:  defm "NSADB: needs the 64K Graphics CP/M video",13,10,'$'
msg_not_found:  defm "NSADB: program not found",13,10,'$'
msg_read_error: defm "NSADB: read error",13,10,'$'
msg_bios:       defm "NSADB: the BIOS jump table is not the one of CP/M",13,10,'$'
msg_too_large:  defm "NSADB: program too large",13,10,'$'

wboot_entry:    defw    0                       ; The BIOS jump table entry that is patched
wboot_orig:     defw    0
args:           defw    0
