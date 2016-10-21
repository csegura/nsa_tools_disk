; Files by name with wildcards, for the small tools: collect the names that a pattern has,
; gather them from several words and process them one after the other.

; The files that the pattern FCB at DE names (the current user area): their names go to the
; table at HL, 12 bytes each (the name and type without the attribute bits, then 1 for a
; read-only file and 2 for a system file, added). B = the most files. Returns A = how many;
; files_over is set when there were more. The files are collected first because opening a
; file in CP/M 2.2 disturbs the search for the next one.
collect_files:
        ld      (collect_table),hl
        ld      a,b
        ld      (collect_max),a
        xor     a
        ld      (collect_count),a
        ld      (files_over),a
        call    dir_first
collect_next:
        jr      c,collect_done
        ld      (collect_entry),hl
        call    collect_known
        jr      z,collect_again
        ld      a,(collect_count)
        ld      b,a
        ld      a,(collect_max)
        cp      b
        jr      nz,collect_room
        ld      a,1
        ld      (files_over),a
        jr      collect_done
collect_room:
        ld      l,b
        ld      h,0
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,de
        add     hl,hl
        add     hl,hl
        ld      de,(collect_table)
        add     hl,de
        ex      de,hl
        ld      hl,(collect_entry)
        inc     hl
        ld      b,11
collect_copy:
        ld      a,(hl)
        and     7Fh
        ld      (de),a
        inc     hl
        inc     de
        djnz    collect_copy
        ld      hl,(collect_entry)
        ld      bc,9
        add     hl,bc
        xor     a
        bit     7,(hl)
        jr      z,collect_system
        ld      a,1
collect_system:
        inc     hl
        bit     7,(hl)
        jr      z,collect_attr
        or      2
collect_attr:
        ld      (de),a
        ld      hl,collect_count
        inc     (hl)
collect_again:
        call    dir_next
        jr      collect_next
collect_done:
        ld      a,(collect_count)
        ret

; Z when the file of the directory entry collect_entry is in the table.
collect_known:
        ld      a,(collect_count)
        or      a
        jr      z,collect_unknown
        ld      b,a
        ld      hl,(collect_table)
collect_known_next:
        push    bc
        push    hl
        ld      de,(collect_entry)
        inc     de
        ld      b,11
collect_compare:
        ld      a,(de)
        and     7Fh
        cp      (hl)
        jr      nz,collect_other
        inc     hl
        inc     de
        djnz    collect_compare
        pop     hl
        pop     bc
        xor     a
        ret
collect_other:
        pop     hl
        ld      bc,12
        add     hl,bc
        pop     bc
        djnz    collect_known_next
collect_unknown:
        or      1
        ret

collect_table:  defw    0
collect_entry:  defw    0
collect_max:    defb    0
collect_count:  defb    0
files_over:     defb    0

; The files that the word names are added to the table all_files: 13 bytes each, the drive
; (0 is the current one), the name and type, and the attributes as collect_files gives
; them (bit 0 read-only, bit 1 system) with the user area in the high four bits, which is
; the current one when the word is gathered. The program defines all_files (MAX_ALL entries),
; all_count, temp_files (MAX_TEMP entries of 12 bytes), `pattern` (an FCB) and `missing`. A
; word that names no file is reported and `missing` is set, unless gather_quiet is set.
gather_word:
        call    get_user
        ld      (gather_user),a
        ld      hl,word
        ld      de,pattern
        call    parse_fcb
        ld      de,pattern
        ld      hl,temp_files
        ld      b,MAX_TEMP
        call    collect_files
        or      a
        jr      nz,gather_have
        ld      a,(gather_quiet)
        or      a
        ret     nz
        ld      hl,word
        call    put_text
        ld      hl,msg_not_found
        call    put_text
        ld      a,1
        ld      (missing),a
        ret
gather_have:
        ld      b,a
        ld      a,(files_over)
        or      a
        call    nz,gather_limit
        ld      hl,temp_files
gather_next:
        ld      a,(all_count)
        cp      MAX_ALL
        jr      c,gather_room
        jr      gather_limit
gather_room:
        push    bc
        push    hl
        ld      l,a
        ld      h,0
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,de
        add     hl,hl
        add     hl,hl
        add     hl,de
        ld      de,all_files
        add     hl,de
        ex      de,hl
        ld      a,(pattern)
        ld      (de),a
        inc     de
        pop     hl
        ld      bc,12
        ldir
        dec     de
        ld      a,(gather_user)
        rlca
        rlca
        rlca
        rlca
        ld      b,a
        ld      a,(de)
        or      b
        ld      (de),a
        push    hl
        ld      hl,all_count
        inc     (hl)
        pop     hl
        pop     bc
        djnz    gather_next
        ret

; The tool takes only the first files: say so.
gather_limit:
        push    bc
        ld      hl,word
        call    put_text
        ld      hl,msg_too_many
        call    put_text
        ld      a,1
        ld      (missing),a
        pop     bc
        ret

gather_user:    defb    0
gather_quiet:   defb    0
msg_too_many:   defm " names more files than this tool holds: only the first ones are used",13,10,0
