; The length of an instruction, from its opcode alone.

; The length in A of the instruction at HL (1 to 4). HL is kept.
instr_length:
        push    hl
        ld      a,(hl)
        cp      0CBh
        jr      z,len_two
        cp      0EDh
        jr      z,len_ed
        cp      0DDh
        jr      z,len_index
        cp      0FDh
        jr      z,len_index
        call    base_length
        pop     hl
        ret
len_two:
        ld      a,2
        pop     hl
        ret
len_ed:
        inc     hl
        ld      a,(hl)
        and     0C7h
        cp      043h
        ld      a,2
        jr      nz,len_done
        ld      a,4
len_done:
        pop     hl
        ret
len_index:
        inc     hl
        ld      a,(hl)
        cp      0CBh
        jr      z,len_four
        cp      0DDh
        jr      z,len_one
        cp      0FDh
        jr      z,len_one
        cp      0EDh
        jr      z,len_one
        ld      b,a
        call    base_length
        inc     a
        ld      c,a
        ld      a,b
        call    uses_hl_memory
        ld      a,c
        jr      nc,len_done
        inc     a
        jr      len_done
len_one:
        ld      a,1
        jr      len_done
len_four:
        ld      a,4
        jr      len_done

; The length in A of the unprefixed instruction with opcode A. Uses D.
base_length:
        ld      d,a
        and     0C7h
        cp      006h
        jr      z,base_two
        cp      0C6h
        jr      z,base_two
        cp      0C2h
        jr      z,base_three
        cp      0C4h
        jr      z,base_three
        ld      a,d
        and     0CFh
        cp      001h
        jr      z,base_three
        ld      a,d
        and     0E7h
        cp      020h
        jr      z,base_two
        cp      022h
        jr      z,base_three
        ld      a,d
        cp      010h
        jr      z,base_two
        cp      018h
        jr      z,base_two
        cp      0C3h
        jr      z,base_three
        cp      0CDh
        jr      z,base_three
        cp      0D3h
        jr      z,base_two
        cp      0DBh
        jr      z,base_two
        ld      a,1
        ret
base_two:
        ld      a,2
        ret
base_three:
        ld      a,3
        ret

; Carry when the opcode A, after DD or FD, has an (IX+d) or (IY+d) operand, which
; adds a byte. Uses B.
uses_hl_memory:
        cp      034h
        jr      c,uses_no
        cp      037h
        jr      c,uses_yes
        cp      040h
        jr      c,uses_no
        cp      0C0h
        jr      nc,uses_no
        cp      076h
        jr      z,uses_no
        ld      b,a
        and     7
        cp      6
        jr      z,uses_yes
        ld      a,b
        cp      080h
        jr      nc,uses_no
        rrca
        rrca
        rrca
        and     7
        cp      6
        jr      z,uses_yes
uses_no:
        or      a
        ret
uses_yes:
        scf
        ret
