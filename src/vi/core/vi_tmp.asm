; Temporary files for the window over a large document.
;
; A temporary file holds pieces of text. Each piece starts on a 128-byte
; record and is padded with 1Ah, so a piece is named by its first record and
; its byte count and the file never needs a partial-record update. A file
; works as a stack: the caller keeps the first record and the length of every
; piece, writes a piece at the end and gives the space back with tmp_release.
;
; The caller selects the file with (tmpf) and uses the BDOS random-record
; calls through the FCB at the start of the file's TMPF block. The includer
; provides tmp_buf, a 128-byte buffer. Registers other
; than the results are not kept. Carry is set on a disk or directory error.

TMPF_RAND:      equ     33              ; Random record number in the FCB
TMPF_END:       equ     36              ; First free record
TMPF_SIZE:      equ     38

; Create the empty temporary file (tmpf). HL = its 11-byte name, A = the drive
; code of the FCB (0 is the current drive).
tmp_create:
        push    af
        push    hl
        ld      hl,(tmpf)
        ld      b,TMPF_SIZE
tmp_clear:
        ld      (hl),0
        inc     hl
        djnz    tmp_clear
        pop     hl
        ld      de,(tmpf)
        inc     de
        ld      bc,11
        ldir
        ld      hl,(tmpf)
        pop     af
        ld      (hl),a
        call    tmp_erase       ; Remove a file left by an earlier run.
        ld      de,(tmpf)
        ld      c,22
        call    BDOS
        inc     a
        jp      z,tmp_fail
        or      a
        ret

; Append HL..HL+BC-1 at the end of the file. The first record of the piece is
; returned in (tmp_rec).
tmp_write:
        ld      (tmp_src),hl
        ld      (tmp_left),bc
        call    tmp_end_get
        ld      (tmp_rec),de
tmp_write_loop:
        ld      bc,(tmp_left)
        ld      a,b
        or      c
        ret     z
        call    tmp_next_count
        push    bc
        ld      hl,tmp_buf
        ld      de,tmp_buf+1
        ld      (hl),01Ah
        ld      bc,127
        ldir
        pop     bc
        ld      hl,(tmp_src)
        ld      de,tmp_buf
        ldir
        ld      (tmp_src),hl
        ld      de,tmp_buf
        ld      c,26
        call    BDOS
        call    tmp_end_get
        call    tmp_seek
        ld      de,(tmpf)
        ld      c,34
        call    BDOS
        or      a
        jp      nz,tmp_fail
        call    tmp_end_get
        inc     de
        call    tmp_end_set
        jr      tmp_write_loop

; Read DE..DE+BC-1 from the piece that starts at record (tmp_rec). The first
; record after the piece is left in (tmp_rec).
tmp_read:
        ld      (tmp_src),de
        ld      (tmp_left),bc
tmp_read_loop:
        ld      bc,(tmp_left)
        ld      a,b
        or      c
        ret     z
        call    tmp_next_count
        push    bc
        ld      de,tmp_buf
        ld      c,26
        call    BDOS
        ld      de,(tmp_rec)
        call    tmp_seek
        inc     de
        ld      (tmp_rec),de
        ld      de,(tmpf)
        ld      c,33
        call    BDOS
        pop     bc
        or      a
        jp      nz,tmp_fail
        ld      hl,tmp_buf
        ld      de,(tmp_src)
        ldir
        ld      (tmp_src),de
        jr      tmp_read_loop

; Give back the space from record DE to the end of the file.
tmp_release:
        jr      tmp_end_set

; Close and delete the file (tmpf).
tmp_erase:
        ld      de,(tmpf)
        ld      c,16
        call    BDOS
        ld      de,(tmpf)
        ld      c,19
        jp      BDOS

tmp_fail:
        scf
        ret

; BC = the bytes of the next record to move: (tmp_left) or 128 if less.
; (tmp_left) is reduced by BC.
tmp_next_count:
        ld      hl,(tmp_left)
        ld      bc,128
        or      a
        sbc     hl,bc
        jr      nc,tmp_count_full
        ld      bc,(tmp_left)
        ld      hl,0
tmp_count_full:
        ld      (tmp_left),hl
        ret

; Set the random record number of the file (tmpf) to DE.
tmp_seek:
        ld      hl,(tmpf)
        ld      bc,TMPF_RAND
        add     hl,bc
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      (hl),0
        ret

tmp_end_get:
        ld      hl,(tmpf)
        ld      bc,TMPF_END
        add     hl,bc
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ret

tmp_end_set:
        ld      hl,(tmpf)
        ld      bc,TMPF_END
        add     hl,bc
        ld      (hl),e
        inc     hl
        ld      (hl),d
        or      a
        ret

tmpf:           defw 0
tmp_rec:        defw 0
tmp_src:        defw 0
tmp_left:       defw 0
