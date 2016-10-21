; The debug file (PROG.DBG, made by tools/mkdbg.py): where the lines of the source are,
; the labels and the text of the source. See docs/nsadb.md for the layout.
;
; The index (the first word of each record of the tables, the files, the text index) is
; read into memory; the tables themselves stay on the disk and are read one record at a
; time, so a line is found with one record read. Two records are kept: A for the tables
; and B for the text.
;
; A key is the number of a line among all the lines of the files, which follow each
; other, from 1; 0 is no line.

NSH_FILES:      equ     5
NSH_ADDR:       equ     6               ; The entries of the line table by address
NSH_LINE:       equ     8               ; ... of the line table by line
NSH_SYMBOLS:    equ     10
NSH_BLOB:       equ     12              ; The records of the index
NSH_RADDR:      equ     14              ; The first record of each table
NSH_RLINE:      equ     16
NSH_RNAME:      equ     18
NSH_RSYMADDR:   equ     20
NSH_RTEXT:      equ     22
NSH_OFILES:     equ     24              ; Where each part of the index is in dbg_blob
NSH_OADDR:      equ     26
NSH_OLINE:      equ     28
NSH_OSYMADDR:   equ     30
NSH_OTEXT:      equ     32
NSH_RECORDS:    equ     34              ; The records of the COM file the debug file is for
NSD_BLOB_MAX:   equ     16
SYMBOL_SIZE:    equ     32
SYMBOL_ADDRESS: equ     30

; Open the debug file of the program and read its index. dbg_present is set when the
; file is there and good. The DMA address goes back to the one of the program.
dbg_load:
        xor     a
        ld      (dbg_present),a
        ld      (dbg_status),a
        ld      e,0FFh
        ld      c,32
        call    BDOS
        ld      (dbg_user),a
        ld      h,a
        ld      l,a
        ld      (dbg_tag_a),hl
        ld      (dbg_tag_b),hl
        ld      hl,dbg_fcb
        ld      (hl),0
        ld      de,dbg_fcb+1
        ld      bc,35
        ldir
        ld      a,(nsd_prog_fcb)
        or      a
        jr      nz,dbg_drive
        ld      c,25
        call    BDOS
        inc     a
dbg_drive:
        ld      (dbg_fcb),a
        ld      hl,nsd_prog_fcb+1
        ld      de,dbg_fcb+1
        ld      bc,8
        ldir
        ld      hl,dbg_extension
        ld      de,dbg_fcb+9
        ld      bc,3
        ldir
        ld      de,dbg_fcb
        ld      c,15
        call    BDOS
        inc     a
        jr      z,dbg_load_end
        ld      de,0
        ld      hl,dbg_hdr
        call    dbg_read_record
        jr      c,dbg_load_end
        ld      hl,dbg_hdr
        ld      de,dbg_magic
        ld      b,5
dbg_load_check:
        ld      a,(de)
        cp      (hl)
        jr      nz,dbg_load_bad
        inc     hl
        inc     de
        djnz    dbg_load_check
        ld      hl,(dbg_hdr+NSH_RECORDS)
        ld      de,(nsd_prog_fcb+33)
        or      a
        sbc     hl,de
        jr      nz,dbg_load_bad
        ld      a,(dbg_hdr+NSH_BLOB)
        cp      NSD_BLOB_MAX+1
        jr      nc,dbg_load_bad
        ld      (dbg_count),a
        ld      de,1
        ld      hl,dbg_blob
dbg_load_blob:
        ld      a,(dbg_count)
        or      a
        jr      z,dbg_load_ready
        push    de
        push    hl
        call    dbg_read_record
        pop     hl
        pop     de
        jr      c,dbg_load_bad
        ld      bc,128
        add     hl,bc
        inc     de
        ld      a,(dbg_count)
        dec     a
        ld      (dbg_count),a
        jr      dbg_load_blob
dbg_load_ready:
        ld      hl,(dbg_hdr+NSH_ADDR)
        call    dbg_sectors_32
        ld      (dbg_secs_addr),hl
        ld      hl,(dbg_hdr+NSH_LINE)
        call    dbg_sectors_32
        ld      (dbg_secs_line),hl
        ld      hl,(dbg_hdr+NSH_SYMBOLS)
        call    dbg_sectors_4
        ld      (dbg_secs_sym),hl
        ld      a,1
        ld      (dbg_present),a
        ld      (dbg_status),a
        jr      dbg_load_end
dbg_load_bad:
        ld      a,2
        ld      (dbg_status),a
dbg_load_end:
        ld      de,TAIL
        ld      c,26
        jp      bdos_next

dbg_magic:      defm    "NSDB",1
dbg_extension:  defm    "DBG"

; The record DE of the debug file goes to the buffer at HL. Carry when it cannot.
dbg_read_record:
        ld      (dbg_fcb+33),de
        xor     a
        ld      (dbg_fcb+35),a
        ex      de,hl
        ld      c,26
        call    bdos_next               ; not BDOS: the hook keeps the DMA address of the program
        ld      e,0FFh
        ld      c,32
        call    BDOS
        push    af
        ld      a,(dbg_user)
        ld      e,a
        ld      c,32
        call    BDOS
        ld      de,dbg_fcb
        ld      c,33
        call    BDOS
        ld      b,a
        pop     af
        ld      e,a
        ld      c,32
        call    BDOS
        ld      a,b
        or      a
        ret     z
        scf
        ret

; The record DE in cache A (the tables) or B (the text); HL is its buffer. Carry when
; it cannot be read.
dbg_table_record:
        ld      hl,(dbg_tag_a)
        or      a
        sbc     hl,de
        ld      hl,dbg_buf_a
        ret     z
        ld      (dbg_tag_a),de
        push    hl
        call    dbg_read_record
        pop     hl
        ret     nc
        ld      de,0
        ld      (dbg_tag_a),de
        ret

dbg_text_record:
        ld      hl,(dbg_tag_b)
        or      a
        sbc     hl,de
        ld      hl,dbg_buf_b
        ret     z
        ld      (dbg_tag_b),de
        push    hl
        call    dbg_read_record
        pop     hl
        ret     nc
        ld      de,0
        ld      (dbg_tag_b),de
        ret

; ---------- searching the index ----------
; HL = words in ascending order, BC = how many, DE = a key. Returns HL = the index of
; the last word that is not above the key; carry when all are.
dbg_search:
        push    ix
        push    hl
        pop     ix
        ld      hl,0
search_next:
        ld      a,b
        or      c
        jr      z,search_done
        ld      a,e
        sub     (ix+0)
        ld      a,d
        sbc     a,(ix+1)
        jr      c,search_done
        inc     ix
        inc     ix
        inc     hl
        dec     bc
        jr      search_next
search_done:
        pop     ix
        ld      a,h
        or      l
        jr      z,search_none
        dec     hl
        or      a
        ret
search_none:
        scf
        ret

; HL = (HL + 31) / 32 and (HL + 3) / 4: the records of a table of 4-byte entries and
; of one of 32-byte entries.
dbg_sectors_32:
        ld      de,31
        ld      b,5
        jr      sectors_divide
dbg_sectors_4:
        ld      de,3
        ld      b,2
sectors_divide:
        add     hl,de
sectors_shift:
        srl     h
        rr      l
        djnz    sectors_shift
        ret

; A = the entries in the record HL of a table of DE entries that has 1 << B of them in a
; record: all of them, or the rest in the last one.
sector_entries:
        push    bc
sector_first:
        add     hl,hl
        djnz    sector_first
        pop     bc
        ex      de,hl
        or      a
        sbc     hl,de
        ld      a,1
        ld      c,b
        inc     c
sector_per:
        dec     c
        jr      z,sector_have
        add     a,a
        jr      sector_per
sector_have:
        ld      c,a
        ld      a,h
        or      a
        ld      a,c
        ret     nz
        ld      a,l
        cp      c
        ret     c
        ld      a,c
        ret

; ---------- lines ----------
; DE = an address. HL = the key of the line it is in; 0 when it is in none.
dbg_find_line:
        ld      a,(dbg_present)
        or      a
        jr      z,key_none
        ld      hl,(dbg_hdr+NSH_OADDR)
        ld      bc,dbg_blob
        add     hl,bc
        ld      bc,(dbg_secs_addr)
        push    de
        call    dbg_search
        pop     de
        jr      c,key_none
        ld      (dbg_sector),hl
        ld      bc,(dbg_hdr+NSH_RADDR)
        add     hl,bc
        push    de
        ex      de,hl
        call    dbg_table_record
        pop     de
        jr      c,key_none
        push    hl
        pop     ix
        ld      hl,(dbg_sector)
        push    de
        ld      de,(dbg_hdr+NSH_ADDR)
        ld      b,5
        call    sector_entries
        pop     de
        ld      b,a
        ld      hl,0
find_line_next:
        ld      a,e
        sub     (ix+0)
        ld      a,d
        sbc     a,(ix+1)
        ret     c
        ld      l,(ix+2)
        ld      h,(ix+3)
        inc     ix
        inc     ix
        inc     ix
        inc     ix
        djnz    find_line_next
        ret
key_none:
        ld      hl,0
        ret

; DE = a key. HL = the address of the first line at or after it, in the same file, that
; has code, and BC = the key of that line; carry when there is none.
dbg_find_address:
        ld      a,(dbg_present)
        or      a
        jp      z,address_none
        push    de
        call    dbg_key_file
        call    dbg_file_entry
        ld      de,12
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        ex      de,hl
        add     hl,bc
        ld      (dbg_limit),hl
        pop     de
        ld      hl,(dbg_hdr+NSH_OLINE)
        ld      bc,dbg_blob
        add     hl,bc
        ld      bc,(dbg_secs_line)
        push    de
        call    dbg_search
        pop     de
        jr      nc,address_sector
        ld      hl,0
address_sector:
        ld      (dbg_sector),hl
address_read:
        ld      hl,(dbg_secs_line)
        ld      bc,(dbg_sector)
        or      a
        sbc     hl,bc
        jr      z,address_none
        jr      c,address_none
        ld      hl,(dbg_sector)
        ld      bc,(dbg_hdr+NSH_RLINE)
        add     hl,bc
        push    de
        ex      de,hl
        call    dbg_table_record
        pop     de
        jr      c,address_none
        push    hl
        pop     ix
        ld      hl,(dbg_sector)
        push    de
        ld      de,(dbg_hdr+NSH_LINE)
        ld      b,5
        call    sector_entries
        pop     de
        ld      b,a
address_scan:
        ld      a,(ix+0)
        sub     e
        ld      a,(ix+1)
        sbc     a,d
        jr      c,address_skip
        ld      hl,(dbg_limit)
        ld      a,(ix+0)
        sub     l
        ld      a,(ix+1)
        sbc     a,h
        jr      nc,address_none
        ld      c,(ix+0)
        ld      b,(ix+1)
        ld      l,(ix+2)
        ld      h,(ix+3)
        or      a
        ret
address_skip:
        inc     ix
        inc     ix
        inc     ix
        inc     ix
        djnz    address_scan
        ld      hl,(dbg_sector)
        inc     hl
        ld      (dbg_sector),hl
        jr      address_read
address_none:
        scf
        ret

; ---------- labels ----------
; HL = a name in capitals, ended by a zero. HL = its address; carry when it is not a label.
; The labels by name are searched on the disk by halving, as there can be hundreds.
dbg_find_symbol:
        ld      a,(dbg_present)
        or      a
        jr      z,symbol_none
        ld      (sym_name),hl
        ld      hl,0
        ld      (sym_low),hl
        ld      hl,(dbg_hdr+NSH_SYMBOLS)
        ld      (sym_high),hl
symbol_loop:
        ld      hl,(sym_high)
        ld      de,(sym_low)
        or      a
        sbc     hl,de
        jr      z,symbol_none
        srl     h
        rr      l
        add     hl,de
        ld      (sym_mid),hl
        srl     h
        rr      l
        srl     h
        rr      l
        ld      bc,(dbg_hdr+NSH_RNAME)
        add     hl,bc
        ex      de,hl
        call    dbg_table_record
        jr      c,symbol_none
        ld      a,(sym_mid)
        and     3
        rrca
        rrca
        rrca
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (sym_entry),hl
        ld      de,(sym_name)
symbol_compare:
        ld      a,(de)
        cp      (hl)
        jr      nz,symbol_differ
        or      a
        jr      z,symbol_found
        inc     hl
        inc     de
        jr      symbol_compare
symbol_differ:
        jr      c,symbol_before
        ld      hl,(sym_mid)
        inc     hl
        ld      (sym_low),hl
        jr      symbol_loop
symbol_before:
        ld      hl,(sym_mid)
        ld      (sym_high),hl
        jr      symbol_loop
symbol_found:
        ld      hl,(sym_entry)
        ld      de,SYMBOL_ADDRESS
        add     hl,de
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        or      a
        ret
symbol_none:
        scf
        ret

; DE = an address. The name of the label at or before it is copied to sym_buf, HL is the
; distance to it; carry when there is none.
dbg_symbol_at:
        ld      a,(dbg_present)
        or      a
        jr      z,symbol_none
        ld      hl,(dbg_hdr+NSH_OSYMADDR)
        ld      bc,dbg_blob
        add     hl,bc
        ld      bc,(dbg_secs_sym)
        push    de
        call    dbg_search
        pop     de
        jr      c,symbol_none
        ld      (dbg_sector),hl
        ld      bc,(dbg_hdr+NSH_RSYMADDR)
        add     hl,bc
        push    de
        ex      de,hl
        call    dbg_table_record
        pop     de
        jr      c,symbol_none
        push    hl
        pop     ix
        ld      hl,(dbg_sector)
        push    de
        ld      de,(dbg_hdr+NSH_SYMBOLS)
        ld      b,2
        call    sector_entries
        pop     de
        ld      b,a
        push    ix
        pop     hl
        ld      (sym_entry),hl
symbol_at_next:
        ld      a,e
        sub     (ix+SYMBOL_ADDRESS)
        ld      a,d
        sbc     a,(ix+SYMBOL_ADDRESS+1)
        jr      c,symbol_at_found
        push    ix
        pop     hl
        ld      (sym_entry),hl
        ld      bc,SYMBOL_SIZE
        add     ix,bc
        djnz    symbol_at_next
symbol_at_found:
        ld      hl,(sym_entry)
        ld      bc,SYMBOL_ADDRESS
        add     hl,bc
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        ex      de,hl
        or      a
        sbc     hl,bc
        push    hl
        ld      hl,(sym_entry)
        ld      de,sym_buf
        ld      bc,SYMBOL_ADDRESS
        ldir
        pop     hl
        or      a
        ret

; ---------- the text of the source ----------
; A = a file. HL = its entry of the file table: name (12), lines (word), index (word).
dbg_file_entry:
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,(dbg_hdr+NSH_OFILES)
        add     hl,de
        ld      de,dbg_blob
        add     hl,de
        ret

; A = a file. HL = how many lines it has.
dbg_file_lines:
        call    dbg_file_entry
        ld      de,12
        jr      file_word

; A = a file. HL = the key of its first line.
dbg_file_base:
        call    dbg_file_entry
        ld      de,14
file_word:
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ret

; DE = a key. A = its file and HL = its line in the file.
dbg_key_file:
        push    ix
        ld      hl,(dbg_hdr+NSH_OFILES)
        ld      bc,dbg_blob+14
        add     hl,bc
        push    hl
        pop     ix
        ld      a,(dbg_hdr+NSH_FILES)
        ld      b,a
        xor     a
        ld      (dbg_best),a
        ld      c,0
        ld      hl,1
key_file_next:
        ld      a,e
        sub     (ix+0)
        ld      a,d
        sbc     a,(ix+1)
        jr      c,key_file_done
        ld      a,c
        ld      (dbg_best),a
        ld      l,(ix+0)
        ld      h,(ix+1)
        inc     c
        push    bc
        ld      bc,16
        add     ix,bc
        pop     bc
        djnz    key_file_next
key_file_done:
        ex      de,hl
        or      a
        sbc     hl,de
        inc     hl
        pop     ix
        ld      a,(dbg_best)
        ret

; Start reading the text at line DE of the file A. The first call of dbg_text_line then
; gives that line.
dbg_seek_line:
        push    de
        call    dbg_file_base
        pop     de
        add     hl,de
        dec     hl
        ex      de,hl

; Start reading the text at the line with the key DE.
dbg_seek_key:
        dec     de
        ld      a,e
        and     15
        ld      (dbg_skip),a
        srl     d
        rr      e
        srl     d
        rr      e
        srl     d
        rr      e
        srl     d
        rr      e
        ld      h,d
        ld      l,e
        add     hl,hl
        add     hl,de
        ld      de,(dbg_hdr+NSH_OTEXT)
        add     hl,de
        ld      de,dbg_blob
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        ld      (dbg_text_offset),a
        ld      hl,(dbg_hdr+NSH_RTEXT)
        add     hl,de
        ld      (dbg_text_record_no),hl
        ld      a,(dbg_skip)
        ld      b,a
seek_skip:
        ld      a,b
        or      a
        ret     z
        push    bc
        call    dbg_skip_line
        pop     bc
        dec     b
        jr      seek_skip

; The next character of the text in A; carry at the end of the file.
dbg_text_char:
        ld      a,(dbg_text_offset)
        cp      128
        jr      c,text_char_ready
        ld      hl,(dbg_text_record_no)
        inc     hl
        ld      (dbg_text_record_no),hl
        xor     a
        ld      (dbg_text_offset),a
text_char_ready:
        ld      de,(dbg_text_record_no)
        call    dbg_text_record
        ret     c
        ld      a,(dbg_text_offset)
        ld      e,a
        ld      d,0
        add     hl,de
        ld      a,(hl)
        ld      hl,dbg_text_offset
        inc     (hl)
        or      a
        ret

dbg_skip_line:
        call    dbg_text_char
        ret     c
        cp      0Dh
        jr      nz,dbg_skip_line
        ret

; The next line of text goes to the buffer at DE, ended by a zero and cut to B
; characters. Carry at the end of the file.
dbg_text_line:
        push    de
        push    bc
        call    dbg_text_char
        pop     bc
        pop     de
        jr      c,text_line_end
        cp      0Dh
        jr      z,text_line_end
        ld      c,a
        ld      a,b
        or      a
        jr      z,dbg_text_line
        ld      a,c
        ld      (de),a
        inc     de
        dec     b
        jr      dbg_text_line
text_line_end:
        push    af
        xor     a
        ld      (de),a
        pop     af
        ret
