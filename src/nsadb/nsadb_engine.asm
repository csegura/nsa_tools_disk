; The engine: breakpoints, and running the program for a go or a step. The Z80 has no
; trace mode, so a step finds where the instruction goes on and plants a breakpoint
; (RST 38h) at each place it can go; then the program runs until one is hit.

; ---------- the breakpoints of the user ----------
; Find the breakpoint at HL. Z when found, with DE at its entry.
bp_find:
        ld      a,(nsd_bp_n)
        ld      b,a
        ld      de,nsd_bp_tab
bp_find_next:
        ld      a,b
        or      a
        jr      z,bp_missing
        ld      a,(de)
        cp      l
        jr      nz,bp_find_skip
        inc     de
        ld      a,(de)
        dec     de
        cp      h
        ret     z
bp_find_skip:
        inc     de
        inc     de
        inc     de
        inc     de
        djnz    bp_find_next
bp_missing:
        or      1
        ret

; Add a breakpoint at HL on the line with the key BC. Carry when the table is full.
bp_add:
        ld      a,(nsd_bp_n)
        cp      NSD_BP_MAX
        jr      nc,bp_full
        push    hl
        add     a,a
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,nsd_bp_tab
        add     hl,de
        pop     de
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      (hl),c
        inc     hl
        ld      (hl),b
        ld      hl,nsd_bp_n
        inc     (hl)
        or      a
        ret
bp_full:
        scf
        ret

; Remove the breakpoint entry at DE.
bp_remove:
        ld      hl,nsd_bp_n
        dec     (hl)
        ld      a,(hl)
        add     a,a
        add     a,a
        ld      c,a
        ld      b,0
        ld      hl,nsd_bp_tab
        ex      de,hl
        push    hl
        or      a
        sbc     hl,de
        ex      de,hl
        ld      l,c
        ld      h,b
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l
        pop     de
        ld      h,d
        ld      l,e
        inc     hl
        inc     hl
        inc     hl
        inc     hl
        ld      a,b
        or      c
        ret     z
        ldir
        ret

; ---------- planting ----------
; Put RST 38h at HL, and keep the byte that was there. NZ when the byte is not RAM.
plant:
        push    hl
        ld      a,(nsd_plant_n)
        ld      e,a
        add     a,a
        add     a,e
        ld      e,a
        ld      d,0
        ld      hl,nsd_plant_tab
        add     hl,de
        ex      de,hl
        pop     hl
        ld      a,l
        ld      (de),a
        inc     de
        ld      a,h
        ld      (de),a
        inc     de
        ld      a,(hl)
        ld      (de),a
        push    hl
        ld      hl,nsd_plant_n
        inc     (hl)
        pop     hl
        cpl
        ld      (hl),a
        cp      (hl)
        ret     nz
        ld      (hl),0FFh
        ret

; Put every original byte back, last one first, because two breakpoints at one
; address keep the RST of the first as their original byte.
unplant_all:
        ld      a,(nsd_plant_n)
        or      a
        ret     z
        ld      b,a
        ld      e,a
        add     a,a
        add     a,e
        ld      e,a
        ld      d,0
        ld      hl,nsd_plant_tab
        add     hl,de
unplant_next:
        dec     hl
        ld      c,(hl)
        dec     hl
        ld      d,(hl)
        dec     hl
        ld      e,(hl)
        ld      a,c
        ld      (de),a
        djnz    unplant_next
        xor     a
        ld      (nsd_plant_n),a
        ret

; Plant the address to go to, if there is one, the temporary breakpoints of
; nsd_next_tab, then the ones of the user except the one at DE (the instruction that
; runs first). NZ when one is not in RAM.
plant_all:
        ld      a,(nsd_goto_on)
        or      a
        jr      z,plant_temporary
        push    de
        ld      hl,(nsd_goto)
        call    plant
        pop     de
        ret     nz
plant_temporary:
        ld      a,(nsd_next_n)
        ld      b,a
        ld      hl,nsd_next_tab
plant_temp_next:
        ld      a,b
        or      a
        jr      z,plant_user
        ld      c,(hl)
        inc     hl
        push    hl
        ld      h,(hl)
        ld      l,c
        push    de
        ld      de,(nsd_pc)
        or      a
        sbc     hl,de
        add     hl,de
        pop     de
        jr      z,plant_temp_skip
        push    bc
        push    de
        call    plant
        pop     de
        pop     bc
        pop     hl
        inc     hl
        ret     nz
        djnz    plant_temp_next
        jr      plant_user
; A step that goes back to its own instruction (DJNZ $) cannot have a breakpoint there:
; the loop runs until it goes on.
plant_temp_skip:
        pop     hl
        inc     hl
        djnz    plant_temp_next
plant_user:
        ld      a,(nsd_bp_n)
        ld      b,a
        ld      ix,nsd_bp_tab
plant_user_next:
        ld      a,b
        or      a
        ret     z
        ld      l,(ix+0)
        ld      h,(ix+1)
        inc     ix
        inc     ix
        inc     ix
        inc     ix
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      z,plant_user_skip
        push    bc
        push    de
        call    plant
        pop     de
        pop     bc
        ret     nz
plant_user_skip:
        djnz    plant_user_next
        ret

; ---------- where an instruction goes on ----------
; Fill nsd_next_tab with the addresses where the instruction at nsd_pc can go on. A
; call or a jump into the system (below 0100h or from NSD_BASE up) is not entered: the
; program goes on after the call, or where the system returns. Carry for a HALT.
find_next:
        ld      hl,(nsd_pc)
        call    instr_length
        ld      (nsd_len),a
        xor     a
        ld      (nsd_next_n),a
        ld      hl,(nsd_pc)
        ld      a,(hl)
        ld      c,a
        cp      0DDh
        jr      z,next_index
        cp      0FDh
        jr      z,next_index
        cp      0EDh
        jr      z,next_ed
        cp      0CBh
        jr      z,next_fall
        cp      076h
        jr      z,next_halt
        cp      018h
        jr      z,next_jump_rel
        cp      010h
        jr      z,next_cond_rel
        and     0E7h
        cp      020h
        jr      z,next_cond_rel
        ld      a,c
        cp      0C3h
        jr      z,next_jp
        cp      0CDh
        jr      z,next_call
        cp      0C9h
        jr      z,next_ret
        cp      0E9h
        jr      z,next_jp_hl
        and     0C7h
        cp      0C2h
        jr      z,next_jp_cond
        cp      0C4h
        jr      z,next_call
        cp      0C0h
        jr      z,next_ret_cond
next_fall:
        jr      add_fall
next_halt:
        scf
        ret
next_jump_rel:
        call    rel_target
        jr      add_jump_target
next_cond_rel:
        call    add_fall
        call    rel_target
        jr      add_jump_target
next_jp:
        call    absolute_target
        jr      add_jump_target
next_jp_cond:
        call    add_fall
        jr      next_jp
next_call:
        call    add_fall
        ld      a,(nsd_over)
        or      a
        ret     nz
        call    absolute_target
        jr      add_call_target
next_ret:
        jr      add_return
next_ret_cond:
        call    add_fall
        jr      add_return
next_jp_hl:
        ld      hl,(nsd_hl)
        jr      add_jump_target
next_index:
        inc     hl
        ld      a,(hl)
        cp      0E9h
        jr      nz,next_fall
        ld      hl,(nsd_ix)
        ld      a,c
        cp      0DDh
        jr      z,add_jump_target
        ld      hl,(nsd_iy)
        jr      add_jump_target
next_ed:
        inc     hl
        ld      a,(hl)
        and     0C7h
        cp      045h
        jr      z,add_return
        jr      next_fall

; The address after the instruction.
add_fall:
        ld      hl,(nsd_pc)
        ld      a,(nsd_len)
        ld      e,a
        ld      d,0
        add     hl,de
        jr      add_next

; HL is a place that a jump goes to.
add_jump_target:
        ld      a,h
        or      l
        ret     z
        ld      a,h
        cp      NSD_BASE/256
        jr      nc,add_return
        or      a
        jr      nz,add_next
add_return:
        ld      hl,(nsd_sp)
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ld      a,h
        or      l
        ret     z

; Add HL to the places.
add_next:
        ex      de,hl
        ld      a,(nsd_next_n)
        add     a,a
        ld      c,a
        ld      b,0
        ld      hl,nsd_next_tab
        add     hl,bc
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ld      hl,nsd_next_n
        inc     (hl)
        or      a
        ret

; HL is the place that a call goes to; the system is not entered.
add_call_target:
        ld      a,h
        or      a
        ret     z
        cp      NSD_BASE/256
        ret     nc
        jr      add_next

; HL = the place that the relative jump at nsd_pc goes to.
rel_target:
        ld      hl,(nsd_pc)
        inc     hl
        ld      a,(hl)
        inc     hl
        ld      e,a
        add     a,a
        sbc     a,a
        ld      d,a
        add     hl,de
        ret

; HL = the address of the CALL or JP at nsd_pc.
absolute_target:
        ld      hl,(nsd_pc)
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ret

; ---------- running ----------
; A step runs one instruction: A = 0 enters calls, A = 1 steps over them. It returns
; only when it cannot run, with DE at a message.
do_step:
        ld      (nsd_over),a
        call    find_next
        ld      de,msg_halt
        ret     c
        ld      de,(nsd_pc)
        jr      run_planted

; Go on until a breakpoint. A breakpoint at the instruction that runs first would be
; hit at once, so that one instruction is stepped first and then the program goes on.
do_go:
        ld      hl,(nsd_pc)
        call    bp_find
        jr      nz,go_free
        ld      a,1
        ld      (nsd_go_after),a
        jr      do_step
go_free:
        xor     a
        ld      (nsd_next_n),a
        ld      de,(nsd_pc)

; Plant, and run the program.
run_planted:
        call    plant_all
        jr      nz,run_failed
        ld      de,(nsd_dma)
        ld      c,26
        call    bdos_next
        jp      resume
run_failed:
        call    unplant_all
        ld      de,msg_rom
        ret

; The program stopped at a breakpoint: nsd_pc is the address of the RST.
trap_stop:
        call    unplant_all
        ld      hl,(nsd_pc)
        call    bp_find
        ld      hl,nsd_go_after
        ld      a,(hl)
        ld      (hl),0
        jr      z,stop_breakpoint
        or      a
        jr      z,stop_step
        ld      hl,(nsd_pc)
        ld      de,(nsd_goto)
        or      a
        sbc     hl,de
        ld      a,(nsd_goto_on)
        jr      nz,go_after_continue
        or      a
        jr      nz,stop_stepped
go_after_continue:
        xor     a
        ld      (nsd_next_n),a
        ld      de,(nsd_pc)
        call    run_planted
        jp      stop_message
stop_breakpoint:
        xor     a
        ld      (nsd_line_step),a
        ld      de,msg_breakpoint
        jp      stop_message
; A step by lines goes on while the instructions are in the line where it started.
stop_step:
        ld      a,(nsd_line_step)
        or      a
        jr      z,stop_stepped
        ld      de,(nsd_pc)
        call    dbg_find_line
        ld      de,(nsd_step_key)
        or      a
        sbc     hl,de
        jr      nz,stop_stepped
        ld      a,(nsd_over)
        call    do_step
        xor     a
        ld      (nsd_line_step),a
        jp      stop_message
stop_stepped:
        xor     a
        ld      (nsd_line_step),a
        ld      de,msg_stopped
        jp      stop_message
