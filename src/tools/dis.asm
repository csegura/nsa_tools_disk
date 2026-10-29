; DIS: disassemble a file of Z80 code.
;
;     DIS [-o ORG] [-s START] [-n COUNT] [-f out] [d:]file
;
; Each line has the address, the bytes and the instruction. A .COM file starts at 0100h;
; ORG (hexadecimal) is the address of the first byte, 0100 for a file called .COM and 0
; for another. START (hexadecimal) is the offset in the file to start at (0), and COUNT
; the number of instructions (all of them). With -f the listing goes to a file, which can
; then be read with LESS. The file is read into memory, up to 24,000 bytes. The code is
; read straight on: data in the middle of it shows as instructions.

BDOS:           equ     0005h
TAIL:           equ     0080h
IMAGE_MAX:      equ     24000

        org     0100h
start:  ld      (orig_sp),sp
        ld      sp,stack_top
        ld      hl,flag_out
        ld      de,flag_out+1
        ld      bc,flags_end-flag_out-1
        ld      (hl),0
        ldir
        ld      hl,0FFFFh
        ld      (count),hl
        ld      hl,0
        ld      (start_offset),hl
        ld      (origin),hl
        call    main
        ld      sp,(orig_sp)
        ret

main:   call    args_init
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
        ld      a,(names)
        or      a
        jr      nz,usage
        inc     a
        ld      (names),a
        ld      hl,word
        ld      de,reader
        call    parse_fcb
        jr      main_word
main_run:
        ld      a,(names)
        or      a
        jp      nz,load
usage:  ld      de,msg_usage
        jp      print

; -o ORG, -s START (hexadecimal, with or without 0x), -n COUNT (decimal), -f out and -r (replace the file out)
tool_option:
        cp      'R'
        jr      nz,option_not_r
        ld      a,1
        ld      (flag_replace),a
        or      a
        ret
option_not_r:
        cp      'F'
        jr      z,option_file
        cp      'O'
        jr      z,option_org
        cp      'S'
        jr      z,option_start
        cp      'N'
        scf
        ret     nz
        call    next_word
        ret     c
        ld      hl,word
        call    parse_decimal
        ret     c
        ld      (count),de
        jr      option_done
option_org:
        call    hex_word
        ret     c
        ld      (origin),de
        ld      a,1
        ld      (origin_given),a
        jr      option_done
option_start:
        call    hex_word
        ret     c
        ld      (start_offset),de
        jr      option_done
option_file:
        call    next_word
        ret     c
        ld      hl,word
        ld      de,writer
        call    parse_fcb
        ld      a,1
        ld      (flag_out),a
option_done:
        xor     a
        ld      (word+2),a              ; the word is now the value: the letters of the option end here
        ret

; The next word as a hexadecimal number in DE; carry when it is not.
hex_word:
        call    next_word
        ret     c
        ld      hl,word
        ld      de,0
        ld      b,0
        ld      a,(hl)                  ; a 0x prefix (the CCP makes it 0X) is allowed
        cp      '0'
        jr      nz,hex_next
        inc     hl
        ld      a,(hl)
        cp      'X'
        jr      z,hex_prefix
        dec     hl
        jr      hex_next
hex_prefix:
        inc     hl
hex_next:
        ld      a,(hl)
        or      a
        jr      z,hex_end
        inc     hl
        sub     '0'
        cp      10
        jr      c,hex_digit_ok
        sub     'A'-'0'
        cp      6
        scf
        ret     nc
        add     a,10
hex_digit_ok:
        ld      c,a
        ld      a,b
        cp      4
        scf
        ret     nc
        ex      de,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ex      de,hl
        ld      a,c
        or      e
        ld      e,a
        inc     b
        jr      hex_next
hex_end:
        ld      a,b
        or      a
        ret     nz
        scf
        ret

; Read the file into `image`.
load:
        ld      ix,reader
        call    fcb_clear_tail
        ld      a,(reader+9)
        cp      ' '
        jr      nz,load_open
        ld      hl,reader+9
        ld      (hl),'C'
        inc     hl
        ld      (hl),'O'
        inc     hl
        ld      (hl),'M'
load_open:
        ld      ix,reader
        call    rd_open
        jr      nc,load_binary
        ld      de,msg_no_file
        jp      print
load_binary:
        ld      a,1
        ld      (reader+R_BINARY),a
load_read:
        ld      a,(origin_given)
        or      a
        jr      nz,load_bytes_start
        ld      hl,0100h
        ld      a,(reader+9)
        cp      'C'
        jr      z,load_origin
        ld      hl,0
load_origin:
        ld      (origin),hl
load_bytes_start:
        ld      hl,image
        ld      bc,0
load_bytes:
        push    hl
        push    bc
        ld      ix,reader
        call    rd_getc
        pop     bc
        pop     hl
        jr      c,load_done
        ld      (hl),a
        inc     hl
        inc     bc
        ld      a,b
        cp      IMAGE_MAX/256
        jr      c,load_bytes
        ld      de,msg_truncated
        push    bc
        call    print
        pop     bc
load_done:
        ld      (image_size),bc
        ld      a,(flag_out)
        or      a
        jr      z,list_start
        ld      ix,writer
        call    fcb_clear_tail
        ld      hl,writer+1
        ld      b,11
        ld      a,(hl)
        cp      ' '
        jr      z,list_bad_name
list_wild:
        ld      a,(hl)
        cp      '?'
        jr      z,list_bad_name
        inc     hl
        djnz    list_wild
        ld      de,writer
        ld      c,15
        call    BDOS
        inc     a
        jr      z,list_make
        ld      a,(flag_replace)
        or      a
        jr      nz,list_replace
        ld      de,msg_exists
        jp      print
list_replace:
        ld      de,writer
        ld      c,19
        call    BDOS
list_make:
        ld      ix,writer
        call    fcb_clear_tail
        call    wr_create
        jr      nc,list_start
        ld      de,msg_full
        jp      print
list_bad_name:
        ld      de,msg_bad_out
        jp      print
list_start:
        ld      hl,(origin)
        ld      de,image
        or      a
        sbc     hl,de
        ld      (dis_bias),hl
        ld      hl,(start_offset)
        ld      (position),hl
list_next:
        ld      hl,(count)
        ld      a,h
        or      l
        jr      z,list_end
        ld      hl,(position)
        ld      de,(image_size)
        or      a
        sbc     hl,de
        jr      nc,list_end
        call    list_one
        jr      c,list_failed
        ld      hl,(count)
        dec     hl
        ld      (count),hl
        jr      list_next
list_end:
        ld      a,(flag_out)
        or      a
        ret     z
        ld      ix,writer
        call    wr_close
        ret     nc
list_failed:
        ld      de,msg_full
        jp      print

; One instruction at `position`, as a line in `line`, to the console or to the file.
list_one:
        ld      hl,(position)
        ld      de,image
        add     hl,de
        ld      (position_address),hl
        ld      de,instruction
        call    disassemble
        ld      hl,(dis_ptr)
        ld      de,(position_address)
        or      a
        sbc     hl,de
        ld      a,l
        ld      (length),a
        ld      de,line
        ld      hl,(position)
        ld      bc,(origin)
        add     hl,bc
        call    text_hex16
        ld      a,' '
        ld      (de),a
        inc     de
        ld      (de),a
        inc     de
        ld      hl,(position_address)
        ld      a,(length)
        ld      b,a
        ld      c,4
list_bytes:
        ld      a,b
        or      a
        jr      z,list_blank
        ld      a,(hl)
        inc     hl
        dec     b
        call    text_hex8
        jr      list_gap
list_blank:
        ld      a,' '
        ld      (de),a
        inc     de
        ld      (de),a
        inc     de
list_gap:
        ld      a,' '
        ld      (de),a
        inc     de
        dec     c
        jr      nz,list_bytes
        ld      a,' '
        ld      (de),a
        inc     de
        ld      hl,instruction
list_text:
        ld      a,(hl)
        inc     hl
        or      a
        jr      z,list_text_end
        ld      (de),a
        inc     de
        jr      list_text
list_text_end:
        ld      (de),a
        ld      hl,(position)
        ld      a,(length)
        ld      c,a
        ld      b,0
        add     hl,bc
        ld      (position),hl
        ld      a,(flag_out)
        or      a
        jr      nz,list_to_file
        ld      hl,line
        call    put_text
        call    print_crlf
        or      a
        ret
list_to_file:
        ld      hl,line
list_file_next:
        ld      a,(hl)
        or      a
        jr      z,list_file_end
        inc     hl
        push    hl
        ld      ix,writer
        call    wr_putc
        pop     hl
        ret     c
        jr      list_file_next
list_file_end:
        ld      ix,writer
        ld      a,13
        call    wr_putc
        ret     c
        ld      a,10
        jp      wr_putc

; HL as four hexadecimal digits and A as two, to the text at DE.
text_hex16:
        push    hl
        ld      a,h
        call    text_hex8
        pop     hl
        ld      a,l
text_hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    text_nibble
        pop     af
text_nibble:
        and     0Fh
        add     a,'0'
        cp      '9'+1
        jr      c,text_store
        add     a,'A'-'0'-10
text_store:
        ld      (de),a
        inc     de
        ret

        include "cpm_fcb.asm"
        include "cpm_args.asm"
        include "cpm_io.asm"
        include "decimal.asm"
        include "nsadb_disasm.asm"

msg_usage:      defm "Usage: DIS [-o ORG] [-s START] [-n COUNT] [-f out] [d:]file",13,10,'$'
msg_exists:     defm "DIS: the file out is there (-r replaces it)",13,10,'$'
msg_bad_out:    defm "DIS: the file out needs a name without * or ?",13,10,'$'
msg_no_file:    defm "DIS: the file is not there",13,10,'$'
msg_truncated:  defm "DIS: the file is longer than 24,000 bytes; the rest is not shown",13,10,'$'
msg_full:       defm "DIS: the disk or the directory is full",13,10,'$'
args:           defw 0

image_end:
flag_out:       equ     image_end
flag_replace:   equ     flag_out+1
names:          equ     flag_replace+1
origin_given:   equ     names+1
length:         equ     origin_given+1
flags_end:      equ     length+1
orig_sp:        equ     flags_end
args_pos:       equ     orig_sp+2
count:          equ     args_pos+2
origin:         equ     count+2
start_offset:   equ     origin+2
position:       equ     start_offset+2
position_address: equ   position+2
image_size:     equ     position_address+2
dis_ptr:        equ     image_size+2
dis_index:      equ     dis_ptr+2
dis_plain:      equ     dis_index+1
dis_op:         equ     dis_plain+1
dis_disp:       equ     dis_op+1
dis_bias:       equ     dis_disp+1
numbuf:         equ     dis_bias+2
work:           equ     numbuf+8
word:           equ     work+130
instruction:    equ     word+64
line:           equ     instruction+40
dir_buffer:     equ     line+80
reader:         equ     dir_buffer+128
writer:         equ     reader+R_SIZE
stack_low:      equ     writer+W_SIZE
stack_top:      equ     stack_low+128
image:          equ     stack_top
