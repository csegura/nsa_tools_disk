; A Z80 disassembler. disassemble: HL = the address of the instruction, DE = a buffer
; for its text, ended by a zero. It returns with DE after the text and dis_ptr after
; the instruction. The text is the one of the emulator's disassembler: capitals, hex
; numbers with an H (a 0 first when a letter would be first), decimal displacements.
;
; DE is the output pointer in every routine here. The bytes are read at dis_ptr. The
; targets of relative jumps are shown with dis_bias added: the difference between the
; address that the code is meant to run at and the address that it is read from (0 when it
; is read where it runs).

disassemble:
        ld      (dis_ptr),hl
        xor     a
        ld      (dis_index),a
        call    dis_decode
        xor     a
        ld      (de),a
        ret

dis_decode:
        call    dis_fetch
        cp      0DDh
        jr      z,dis_prefix_ix
        cp      0FDh
        jr      z,dis_prefix_iy
dis_opcode:
        cp      0CBh
        jp      z,dis_cb
        cp      0EDh
        jp      z,dis_ed
        jp      dis_main
dis_prefix_ix:
        ld      a,1
        jr      dis_prefix
dis_prefix_iy:
        ld      a,2
dis_prefix:
        ld      (dis_index),a
        call    dis_fetch
        cp      0DDh
        jr      z,dis_lone_prefix
        cp      0FDh
        jr      z,dis_lone_prefix
        cp      0EDh
        jr      nz,dis_opcode
; A prefix that is followed by another one is a byte of data.
dis_lone_prefix:
        ld      hl,(dis_ptr)
        dec     hl
        ld      (dis_ptr),hl
        call    dis_text
        defm    "DB ",0
        ld      a,(dis_index)
        cp      1
        ld      a,0DDh
        jp      z,emit_byte
        ld      a,0FDh
        jp      emit_byte

; ---------- reading the bytes ----------
dis_fetch:
        ld      hl,(dis_ptr)
        ld      a,(hl)
        inc     hl
        ld      (dis_ptr),hl
        ret

dis_word:
        call    dis_fetch
        ld      c,a
        call    dis_fetch
        ld      h,a
        ld      l,c
        ret

dis_y:
        ld      a,(dis_op)
        rrca
        rrca
        rrca
        and     7
        ret

dis_z:
        ld      a,(dis_op)
        and     7
        ret

; ---------- writing the text ----------
; The text that follows the call, ended by a zero, goes to the output.
dis_text:
        pop     hl
dis_text_next:
        ld      a,(hl)
        inc     hl
        or      a
        jr      z,dis_text_done
        ld      (de),a
        inc     de
        jp      dis_text_next
dis_text_done:
        jp      (hl)

emit_char:
        ld      (de),a
        inc     de
        ret

; HL = the entry A of a table of entries of B bytes.
table_entry:
        ld      c,b
        ld      b,a
table_next:
        ld      a,b
        or      a
        ret     z
        ld      a,l
        add     a,c
        ld      l,a
        jr      nc,table_same
        inc     h
table_same:
        dec     b
        jr      table_next

; Copy the entry A of a table of entries of B characters, leaving out blanks.
emit_entry:
        call    table_entry
emit_fixed:
        ld      a,(hl)
        inc     hl
        cp      ' '
        jr      z,emit_fixed_skip
        ld      (de),a
        inc     de
emit_fixed_skip:
        dec     c
        jr      nz,emit_fixed
        ret

; Copy the text at HL up to its zero.
emit_zstring:
        ld      a,(hl)
        inc     hl
        or      a
        ret     z
        ld      (de),a
        inc     de
        jp      emit_zstring

emit_hex16:
        push    hl
        ld      a,h
        call    emit_hex8
        pop     hl
        ld      a,l
emit_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    emit_nibble
        pop     af
emit_nibble:
        and     0Fh
        add     a,'0'
        cp      '9'+1
        jr      c,emit_char
        add     a,'A'-'0'-10
        jp      emit_char

; A byte as 0FFH or 34H, a word as 1234H or 0ABCDH.
emit_byte:
        push    af
        cp      0A0h
        jr      c,emit_byte_digits
        ld      a,'0'
        call    emit_char
emit_byte_digits:
        pop     af
        call    emit_hex8
        ld      a,'H'
        jp      emit_char

emit_word:
        ld      a,h
        cp      0A0h
        jr      c,emit_word_digits
        ld      a,'0'
        call    emit_char
emit_word_digits:
        call    emit_hex16
        ld      a,'H'
        jp      emit_char

; A displacement: + or - and a decimal number, 0 to 128.
emit_disp:
        ld      b,'+'
        or      a
        jp      p,disp_sign
        neg
        ld      b,'-'
disp_sign:
        ld      c,a
        ld      a,b
        call    emit_char
        ld      a,c
        ld      c,0
        cp      100
        jr      c,disp_tens
        sub     100
        ld      b,a
        ld      a,'1'
        call    emit_char
        ld      a,b
        ld      c,1
disp_tens:
        ld      b,0
disp_ten:
        cp      10
        jr      c,disp_units
        sub     10
        inc     b
        jr      disp_ten
disp_units:
        ld      l,a
        ld      a,b
        or      c
        jr      z,disp_last
        ld      a,b
        add     a,'0'
        call    emit_char
disp_last:
        ld      a,l
        add     a,'0'
        jp      emit_char

; IX or IY, by the prefix.
emit_ix:
        ld      a,'I'
        call    emit_char
        ld      a,(dis_index)
        cp      2
        ld      a,'X'
        jp      nz,emit_char
        ld      a,'Y'
        jp      emit_char

; (HL), or (IX+d) with the displacement read from the instruction.
emit_mem:
        ld      a,(dis_index)
        or      a
        jr      nz,emit_mem_indexed
        call    dis_text
        defm    "(HL)",0
        ret
emit_mem_indexed:
        ld      a,'('
        call    emit_char
        call    emit_ix
        call    dis_fetch
        call    emit_disp
        ld      a,')'
        jp      emit_char

; The register r[A]: B C D E H L (HL) A. After a prefix H and L are IXH and IXL,
; unless the instruction has an (HL) operand as well (dis_plain).
emit_reg:
        cp      6
        jr      z,emit_mem
        ld      b,a
        ld      a,(dis_index)
        or      a
        jr      z,reg_plain
        ld      a,(dis_plain)
        or      a
        jr      nz,reg_plain
        ld      a,b
        cp      4
        jr      z,reg_high
        cp      5
        jr      z,reg_low
reg_plain:
        ld      a,b
        ld      hl,tbl_r
        ld      b,4
        jp      emit_entry
reg_high:
        call    emit_ix
        ld      a,'H'
        jp      emit_char
reg_low:
        call    emit_ix
        ld      a,'L'
        jp      emit_char

; The register pair A of the table at HL; HL is IX or IY after a prefix.
emit_pair:
        cp      2
        jr      nz,pair_table
        ld      b,a
        ld      a,(dis_index)
        or      a
        ld      a,b
        jr      z,pair_table
        jp      emit_ix
pair_table:
        ld      b,2
        jp      emit_entry

emit_hl:
        ld      a,2
        ld      hl,tbl_pair
        jp      emit_pair

emit_comma:
        ld      a,','
        jp      emit_char

; The alu operation y, with "A," for the ones that have it.
emit_alu:
        push    af
        ld      hl,tbl_alu
        ld      b,3
        call    emit_entry
        ld      a,' '
        call    emit_char
        pop     af
        or      a
        jr      z,alu_with_a
        cp      1
        jr      z,alu_with_a
        cp      3
        ret     nz
alu_with_a:
        call    dis_text
        defm    "A,",0
        ret

; HL = the table, A = the index: jump to the address there.
dis_jump:
        add     a,a
        ld      c,a
        ld      b,0
        add     hl,bc
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        jp      (hl)

; ---------- the instructions without prefix ----------
dis_main:
        ld      (dis_op),a
        ld      b,a
        xor     a
        ld      (dis_plain),a
        ld      a,b
        cp      40h
        jr      c,dis_x0
        cp      80h
        jp      c,dis_x1
        cp      0C0h
        jp      c,dis_x2
        jp      dis_x3

dis_x0:
        call    dis_z
        ld      hl,x0_table
        jr      dis_jump
x0_table:
        defw    x0_z0,x0_z1,x0_z2,x0_z3,x0_z4,x0_z5,x0_z6,x0_z7

x0_z0:
        call    dis_y
        or      a
        jr      nz,x0_not_nop
        call    dis_text
        defm    "NOP",0
        ret
x0_not_nop:
        cp      1
        jr      nz,x0_not_ex
        call    dis_text
        defm    "EX AF,AF'",0
        ret
x0_not_ex:
        cp      2
        jr      nz,x0_not_djnz
        call    dis_text
        defm    "DJNZ ",0
        jp      emit_relative
x0_not_djnz:
        cp      3
        jr      nz,x0_jr_cc
        call    dis_text
        defm    "JR ",0
        jp      emit_relative
x0_jr_cc:
        push    af
        call    dis_text
        defm    "JR ",0
        pop     af
        sub     4
        ld      hl,tbl_cc
        ld      b,2
        call    emit_entry
        call    emit_comma

; The target of a relative jump: the address after the instruction plus the byte.
emit_relative:
        call    dis_fetch
        ld      hl,(dis_ptr)
        ld      c,a
        add     a,a
        sbc     a,a
        ld      b,a
        add     hl,bc
        ld      bc,(dis_bias)
        add     hl,bc
        jp      emit_word

x0_z1:
        call    dis_y
        and     1
        jr      nz,x0_add_hl
        call    dis_text
        defm    "LD ",0
        call    dis_y
        srl     a
        ld      hl,tbl_pair
        call    emit_pair
        call    emit_comma
        call    dis_word
        jp      emit_word
x0_add_hl:
        call    dis_text
        defm    "ADD ",0
        call    emit_hl
        call    emit_comma
        call    dis_y
        srl     a
        ld      hl,tbl_pair
        jp      emit_pair

x0_z2:
        call    dis_y
        cp      4
        jr      nc,x0_z2_nn
        ld      hl,txt_indirect
        ld      b,10
        call    table_entry
        jp      emit_zstring
x0_z2_nn:
        cp      5
        jr      c,x0_ld_nn_hl
        jr      z,x0_ld_hl_nn
        cp      6
        jr      z,x0_ld_nn_a
        call    dis_text
        defm    "LD A,(",0
        jp      x0_nn_close
x0_ld_nn_a:
        call    dis_text
        defm    "LD (",0
        call    dis_word
        call    emit_word
        call    dis_text
        defm    "),A",0
        ret
x0_ld_nn_hl:
        call    dis_text
        defm    "LD (",0
        call    dis_word
        call    emit_word
        call    dis_text
        defm    "),",0
        jp      emit_hl
x0_ld_hl_nn:
        call    dis_text
        defm    "LD ",0
        call    emit_hl
        call    dis_text
        defm    ",(",0
x0_nn_close:
        call    dis_word
        call    emit_word
        ld      a,')'
        jp      emit_char

x0_z3:
        call    dis_y
        and     1
        jr      nz,x0_dec_pair
        call    dis_text
        defm    "INC ",0
        jp      x0_pair
x0_dec_pair:
        call    dis_text
        defm    "DEC ",0
x0_pair:
        call    dis_y
        srl     a
        ld      hl,tbl_pair
        jp      emit_pair

x0_z4:
        call    dis_text
        defm    "INC ",0
        call    dis_y
        jp      emit_reg
x0_z5:
        call    dis_text
        defm    "DEC ",0
        call    dis_y
        jp      emit_reg
x0_z6:
        call    dis_text
        defm    "LD ",0
        call    dis_y
        call    emit_reg
        call    emit_comma
        call    dis_fetch
        jp      emit_byte
x0_z7:
        call    dis_y
        ld      hl,tbl_accumulator
        ld      b,4
        jp      emit_entry

; LD r,r' and HALT.
dis_x1:
        ld      a,(dis_op)
        cp      76h
        jr      nz,x1_load
        call    dis_text
        defm    "HALT",0
        ret
x1_load:
        call    dis_y
        cp      6
        jr      z,x1_plain
        call    dis_z
        cp      6
        jr      nz,x1_text
x1_plain:
        ld      a,1
        ld      (dis_plain),a
x1_text:
        call    dis_text
        defm    "LD ",0
        call    dis_y
        call    emit_reg
        call    emit_comma
        call    dis_z
        jp      emit_reg

dis_x2:
        call    dis_y
        call    emit_alu
        call    dis_z
        jp      emit_reg

dis_x3:
        call    dis_z
        ld      hl,x3_table
        jp      dis_jump
x3_table:
        defw    x3_z0,x3_z1,x3_z2,x3_z3,x3_z4,x3_z5,x3_z6,x3_z7

x3_z0:
        call    dis_text
        defm    "RET ",0
        call    dis_y
        ld      hl,tbl_cc
        ld      b,2
        jp      emit_entry
x3_z1:
        call    dis_y
        and     1
        jr      nz,x3_z1_misc
        call    dis_text
        defm    "POP ",0
x3_pair2:
        call    dis_y
        srl     a
        ld      hl,tbl_pair2
        jp      emit_pair
x3_z1_misc:
        call    dis_y
        srl     a
        or      a
        jr      nz,x3_not_ret
        call    dis_text
        defm    "RET",0
        ret
x3_not_ret:
        cp      1
        jr      nz,x3_not_exx
        call    dis_text
        defm    "EXX",0
        ret
x3_not_exx:
        cp      2
        jr      nz,x3_ld_sp
        call    dis_text
        defm    "JP (",0
        call    x3_hl_or_ix
        ld      a,')'
        jp      emit_char
x3_ld_sp:
        call    dis_text
        defm    "LD SP,",0
x3_hl_or_ix:
        ld      a,(dis_index)
        or      a
        jp      nz,emit_ix
        call    dis_text
        defm    "HL",0
        ret

x3_z2:
        call    dis_text
        defm    "JP ",0
        call    dis_y
        ld      hl,tbl_cc
        ld      b,2
        call    emit_entry
        call    emit_comma
        jp      x3_nn
x3_z4:
        call    dis_text
        defm    "CALL ",0
        call    dis_y
        ld      hl,tbl_cc
        ld      b,2
        call    emit_entry
        call    emit_comma
x3_nn:
        call    dis_word
        jp      emit_word

x3_z3:
        call    dis_y
        or      a
        jr      nz,x3_not_jp
        call    dis_text
        defm    "JP ",0
        jp      x3_nn
x3_not_jp:
        cp      2
        jr      nz,x3_not_out
        call    dis_text
        defm    "OUT (",0
        call    dis_fetch
        call    emit_byte
        call    dis_text
        defm    "),A",0
        ret
x3_not_out:
        cp      3
        jr      nz,x3_not_in
        call    dis_text
        defm    "IN A,(",0
        call    dis_fetch
        call    emit_byte
        ld      a,')'
        jp      emit_char
x3_not_in:
        cp      4
        jr      nz,x3_not_ex_sp
        call    dis_text
        defm    "EX (SP),",0
        jp      x3_hl_or_ix
x3_not_ex_sp:
        cp      5
        jr      nz,x3_not_ex_de
        call    dis_text
        defm    "EX DE,HL",0
        ret
x3_not_ex_de:
        cp      6
        jr      nz,x3_ei
        call    dis_text
        defm    "DI",0
        ret
x3_ei:
        call    dis_text
        defm    "EI",0
        ret

x3_z5:
        call    dis_y
        and     1
        jr      nz,x3_call
        call    dis_text
        defm    "PUSH ",0
        jp      x3_pair2
x3_call:
        call    dis_text
        defm    "CALL ",0
        jp      x3_nn

x3_z6:
        call    dis_y
        call    emit_alu
        call    dis_fetch
        jp      emit_byte
x3_z7:
        call    dis_text
        defm    "RST ",0
        call    dis_y
        add     a,a
        add     a,a
        add     a,a
        jp      emit_byte

; ---------- CB ----------
dis_cb:
        ld      a,(dis_index)
        or      a
        jr      z,cb_opcode
        call    dis_fetch
        ld      (dis_disp),a
cb_opcode:
        call    dis_fetch
        ld      (dis_op),a
        and     0C0h
        jr      nz,cb_bit
        call    dis_y
        ld      hl,tbl_rotate
        ld      b,3
        call    emit_entry
        jp      cb_operand_blank
cb_bit:
        rlca
        rlca
        dec     a
        ld      hl,tbl_bit
        ld      b,3
        call    emit_entry
        ld      a,' '
        call    emit_char
        call    dis_y
        add     a,'0'
        call    emit_char
        call    emit_comma
        jp      cb_operand
cb_operand_blank:
        ld      a,' '
        call    emit_char
cb_operand:
        ld      a,(dis_index)
        or      a
        jr      nz,cb_indexed
        call    dis_z
        jp      emit_reg
cb_indexed:
        ld      a,'('
        call    emit_char
        call    emit_ix
        ld      a,(dis_disp)
        call    emit_disp
        ld      a,')'
        call    emit_char
        call    dis_z
        cp      6
        ret     z
        ld      b,a
        ld      a,(dis_op)
        and     0C0h
        cp      40h
        ret     z
        call    emit_comma
        ld      a,b
        ld      hl,tbl_r
        ld      b,4
        jp      emit_entry

; ---------- ED ----------
dis_ed:
        call    dis_fetch
        ld      (dis_op),a
        cp      40h
        jr      c,ed_undefined
        cp      80h
        jr      c,ed_main
        cp      0A0h
        jr      c,ed_undefined
        cp      0C0h
        jr      nc,ed_undefined
        and     4
        jr      nz,ed_undefined
        ld      a,(dis_op)
        and     18h
        rrca
        rrca
        rrca
        add     a,a
        add     a,a
        ld      b,a
        ld      a,(dis_op)
        and     3
        add     a,b
        ld      hl,tbl_block
        ld      b,4
        jp      emit_entry
ed_undefined:
        call    dis_text
        defm    "DB 0EDH,",0
        ld      a,(dis_op)
        jp      emit_byte

ed_main:
        call    dis_z
        ld      hl,ed_table
        jp      dis_jump
ed_table:
        defw    ed_z0,ed_z1,ed_z2,ed_z3,ed_z4,ed_z5,ed_z6,ed_z7

ed_z0:
        call    dis_y
        cp      6
        jr      nz,ed_in_reg
        call    dis_text
        defm    "IN (C)",0
        ret
ed_in_reg:
        call    dis_text
        defm    "IN ",0
        call    dis_y
        ld      hl,tbl_r
        ld      b,4
        call    emit_entry
        call    dis_text
        defm    ",(C)",0
        ret
ed_z1:
        call    dis_y
        cp      6
        jr      nz,ed_out_reg
        call    dis_text
        defm    "OUT (C),0",0
        ret
ed_out_reg:
        call    dis_text
        defm    "OUT (C),",0
        call    dis_y
        ld      hl,tbl_r
        ld      b,4
        jp      emit_entry
ed_z2:
        call    dis_y
        and     1
        jr      nz,ed_adc
        call    dis_text
        defm    "SBC HL,",0
        jp      ed_pair
ed_adc:
        call    dis_text
        defm    "ADC HL,",0
ed_pair:
        call    dis_y
        srl     a
        ld      hl,tbl_pair
        ld      b,2
        jp      emit_entry
ed_z3:
        call    dis_y
        and     1
        jr      nz,ed_load_pair
        call    dis_text
        defm    "LD (",0
        call    dis_word
        call    emit_word
        call    dis_text
        defm    "),",0
        jp      ed_pair
ed_load_pair:
        call    dis_text
        defm    "LD ",0
        call    dis_y
        srl     a
        ld      hl,tbl_pair
        ld      b,2
        call    emit_entry
        call    dis_text
        defm    ",(",0
        call    dis_word
        call    emit_word
        ld      a,')'
        jp      emit_char
ed_z4:
        call    dis_text
        defm    "NEG",0
        ret
ed_z5:
        call    dis_y
        cp      1
        jr      z,ed_reti
        call    dis_text
        defm    "RETN",0
        ret
ed_reti:
        call    dis_text
        defm    "RETI",0
        ret
ed_z6:
        call    dis_text
        defm    "IM ",0
        call    dis_y
        ld      hl,tbl_mode
        ld      c,a
        ld      b,0
        add     hl,bc
        ld      a,(hl)
        jp      emit_char
ed_z7:
        call    dis_y
        ld      hl,txt_special
        ld      b,7
        call    table_entry
        jp      emit_zstring

tbl_r:          defm "B   C   D   E   H   L   (HL)A   "
tbl_cc:         defm "NZZ NCC POPEP M "
tbl_pair:       defm "BCDEHLSP"
tbl_pair2:      defm "BCDEHLAF"
tbl_alu:        defm "ADDADCSUBSBCANDXOROR CP "
tbl_rotate:     defm "RLCRRCRL RR SLASRASLLSRL"
tbl_bit:        defm "BITRESSET"
tbl_accumulator: defm "RLCARRCARLA RRA DAA CPL SCF CCF "
tbl_block:      defm "LDI CPI INI OUTILDD CPD IND OUTDLDIRCPIRINIROTIRLDDRCPDRINDROTDR"
tbl_mode:       defm "00120012"
txt_indirect:   defm "LD (BC),A",0,"LD A,(BC)",0,"LD (DE),A",0,"LD A,(DE)",0
txt_special:    defm "LD I,A",0,"LD R,A",0,"LD A,I",0,"LD A,R",0,"RRD",0,0,0,0,"RLD",0,0,0,0,"NOP",0,0,0,0,"NOP",0,0,0,0
