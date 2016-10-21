; URUN: run a program that is in another user area of CP/M 2.2.
;
;     URUN [/Un] [d:]program [arguments]
;
; The program is loaded from user area n (0 if there is no /Un) of drive d (the
; current drive if there is none) and runs in the user area that was active, so
; it works on the files of that area. ".COM" is assumed without an extension.
;
; The program has to be loaded at 0100h, where URUN itself is, so URUN checks the
; file, copies a small loader to the page just below the CCP, and the loader
; reads the file over URUN, restores the user area and the stack and jumps to
; 0100h. The loader does not depend on its address (it uses only relative
; jumps) because the page depends on the size of the memory.

BDOS:           equ     0005h
TAIL:           equ     0080h
FCB1:           equ     005Ch
FCB2:           equ     006Ch
GAP_PAGES:   equ     9               ; pages below the BDOS: 8 of CCP, 1 free
K_SP:           equ     36              ; In the loader page: the FCB at 0, then
K_USER:         equ     38              ; the stack at entry, the user to go back
K_CODE:         equ     40              ; to and the loader code
K_STACK:        equ     0F0h            ; The stack grows down from here

        org     0100h
start:  ld      (orig_sp),sp
        ld      hl,TAIL
        ld      a,(hl)
        and     07Fh
        ld      c,a
        ld      b,0
        inc     hl
        ld      de,work
        or      a
        jr      z,tail_copied
        ldir
tail_copied:
        xor     a
        ld      (de),a
        ld      hl,work
        call    skip_blanks
        xor     a
        ld      (src_user),a
        ld      a,(hl)
        cp      '/'
        jr      nz,get_program
        inc     hl
        ld      a,(hl)
        cp      'U'
        jr      nz,option_number
        inc     hl
option_number:
        call    read_number
        jp      c,usage
        ld      (src_user),a
        call    skip_blanks
get_program:
        ld      de,tfcb
        call    parse_fcb
        ld      (args),hl
        ld      a,(tfcb+1)
        cp      ' '
        jp      z,usage
        ld      hl,tfcb+1
        ld      b,11
wildcard_scan:
        ld      a,(hl)
        cp      '?'
        jp      z,usage
        inc     hl
        djnz    wildcard_scan
        ld      a,(tfcb+9)
        cp      ' '
        jr      nz,have_extension
        ld      hl,tfcb+9
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
        call    parse_fcb

        ld      c,32
        ld      e,0FFh
        call    BDOS
        ld      (cur_user),a
        ld      a,(src_user)
        ld      e,a
        ld      c,32
        call    BDOS
        ld      de,tfcb
        ld      c,35
        call    BDOS
        ld      de,tfcb
        ld      c,15
        call    BDOS
        inc     a
        jp      z,not_found
        xor     a
        ld      (tfcb+32),a
        ld      a,(0007h)
        sub     GAP_PAGES
        ld      (loader_page),a
        dec     a
        ld      l,a
        ld      h,0
        add     hl,hl
        ld      de,(tfcb+33)
        or      a
        sbc     hl,de
        jp      c,too_large

        ld      a,(loader_page)
        ld      d,a
        ld      e,0
        ld      hl,tfcb
        ld      bc,36
        ldir
        ld      hl,(orig_sp)
        ld      a,l
        ld      (de),a
        inc     de
        ld      a,h
        ld      (de),a
        inc     de
        ld      a,(cur_user)
        ld      (de),a
        inc     de
        xor     a
        ld      (de),a
        inc     de
        ld      hl,loader
        ld      bc,loader_end-loader
        ldir
        ld      a,(loader_page)
        ld      h,a
        ld      l,K_STACK
        ld      sp,hl
        ld      l,K_CODE
        jp      (hl)

; ---------- the loader, copied below the CCP ----------
; Entered with the stack set in its own page, which holds the FCB of the
; program, already open, at the start of the page.
loader:
        ld      hl,0100h
load_record:
        push    hl
        ex      de,hl
        ld      c,26
        call    BDOS
        ld      hl,0
        add     hl,sp
        ld      l,0
        ex      de,hl
        ld      c,20
        call    BDOS
        pop     hl
        or      a
        jr      nz,load_done
        ld      de,128
        add     hl,de
        jr      load_record
load_done:
        ld      hl,0
        add     hl,sp
        ld      l,K_USER
        ld      e,(hl)
        ld      c,32
        call    BDOS
        ld      de,TAIL
        ld      c,26
        call    BDOS
        ld      hl,0
        add     hl,sp
        ld      l,K_SP
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ld      sp,hl
        jp      0100h
loader_end:

; ---------- errors ----------
not_found:
        call    restore_user
        ld      de,msg_run
        call    print
        ld      hl,tfcb+1
        ld      b,8
        call    print_field
        push    hl
        ld      e,'.'
        call    put_char
        pop     hl
        ld      b,3
        call    print_field
        ld      de,msg_not_found
        jr      leave
too_large:
        call    restore_user
        ld      de,msg_too_large
        jr      leave
usage:  ld      de,msg_usage
leave:  call    print
        ld      sp,(orig_sp)
        ret

restore_user:
        ld      a,(cur_user)
        ld      e,a
        ld      c,32
        jp      BDOS

print:  ld      c,9
        jp      BDOS

put_char:
        ld      c,2
        jp      BDOS

; Print the B characters at HL that are not spaces.
print_field:
        ld      a,(hl)
        inc     hl
        cp      ' '
        jr      z,print_skip
        push    hl
        push    bc
        ld      e,a
        call    put_char
        pop     bc
        pop     hl
print_skip:
        djnz    print_field
        ret

; ---------- the command line ----------
; A number of one or two digits at HL, 0 to 15, then a blank or the end. The
; number is returned in A; carry is set when it is not valid.
read_number:
        ld      a,(hl)
        sub     '0'
        jr      c,number_bad
        cp      10
        jr      nc,number_bad
        ld      b,a
        inc     hl
        ld      a,(hl)
        sub     '0'
        jr      c,number_end
        cp      10
        jr      nc,number_end
        inc     hl
        ld      c,a
        ld      a,b
        add     a,a
        add     a,a
        add     a,b
        add     a,a
        add     a,c
        ld      b,a
number_end:
        ld      a,(hl)
        or      a
        jr      z,number_ok
        cp      ' '
        jr      nz,number_bad
number_ok:
        ld      a,b
        cp      16
        ccf
        ret
number_bad:
        scf
        ret

        include "cpm_fcb.asm"

msg_run:        defm "URUN: ",'$'
msg_not_found:  defm " not found",13,10,'$'
msg_too_large:  defm "URUN: program too large",13,10,'$'
msg_usage:      defm "Usage: URUN [/Un] [d:]program [arguments]",13,10,'$'

orig_sp:        defw 0
loader_page:    defb 0
cur_user:       defb 0
src_user:       defb 0
args:           defw 0
tfcb:           defs 36,0
work:           defs 130,0
