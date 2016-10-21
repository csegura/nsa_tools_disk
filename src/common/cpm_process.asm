; Open each of the gathered files (cpm_files.asm) for reading and call the tool on it.

; The reader IX gets the name of the entry HL of all_files and is opened. Carry when the
; file is not there.
open_gathered:
        ld      a,(hl)
        inc     hl
        push    ix
        pop     de
        ld      (de),a
        inc     de
        ld      bc,11
        ldir
        push    ix
        pop     hl
        ld      bc,12
        add     hl,bc
        ld      b,24
        xor     a
open_gathered_zero:
        ld      (hl),a
        inc     hl
        djnz    open_gathered_zero
        jp      rd_open

; Open each of the gathered files and call tool_file, with IX the reader and
; (current_entry) the entry of all_files. The program defines `reader` and current_entry.
; A file that cannot be opened is reported.
process_all:
        ld      a,(all_count)
        or      a
        ret     z
        call    get_user
        ld      (home_user),a
        call    process_files
        ld      a,(home_user)
        jp      set_user
process_files:
        ld      a,(all_count)
        ld      b,a
        ld      hl,all_files
process_next:
        push    bc
        push    hl
        ld      (current_entry),hl
        ld      bc,12
        add     hl,bc
        ld      a,(hl)
        rrca
        rrca
        rrca
        rrca
        and     0Fh
        call    set_user
        ld      hl,(current_entry)
        ld      ix,reader
        call    open_gathered
        jr      nc,process_open
        call    put_entry_name
        ld      hl,msg_not_found
        call    put_text
        jr      process_skip
process_open:
        call    tool_file
process_skip:
        pop     hl
        ld      bc,13
        add     hl,bc
        pop     bc
        djnz    process_next
        ret

; The name of the gathered file at (current_entry): NAME.EXT, with its user area and a colon in
; front (u:NAME.EXT) when show_user is set.
put_entry_name:
        ld      hl,(current_entry)
        ld      a,(show_user)
        or      a
        jr      z,entry_name
        ld      bc,12
        add     hl,bc
        ld      a,(hl)
        rrca
        rrca
        rrca
        rrca
        and     0Fh
        ld      l,a
        ld      h,0
        call    put_number
        ld      e,':'
        call    put_char
        ld      hl,(current_entry)
entry_name:
        inc     hl
        jp      put_file_name

show_user:      defb    0
home_user:      defb    0
