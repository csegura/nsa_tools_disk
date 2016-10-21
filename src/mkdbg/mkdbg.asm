; MKDBG: make the debug file of NSADB (PROG.DBG) from the listing of Microsoft M80 (PROG.PRN).
;
;     MKDBG [-b ADDR] [-d ADDR] [d:]PROG
;
; It does what `tools/mkdbg.py --prn` does on the host (the reference of this program: the
; two make the same file, byte for byte), so a program that is assembled with M80 and linked
; with L80 on the machine can be debugged at the level of the source. PROG.COM has to be
; there too, for its size. The format of the file is in docs/nsadb.md and the listing in
; docs/mkdbg.md.
;
; The listing is read once. The lines of the source go to a temporary file (the file of the
; line, the text, a carriage return); the addresses and the labels are kept in memory in
; tables that stay sorted. Then the tables are written, and the text is copied in one pass
; for each file, so that the lines of each file are together, in order. The header and the
; index go in last, because the index has the place of the lines of the text.

BDOS:           equ     0005h
TAIL:           equ     0080h
MAX_ENTRIES:    equ     3000            ; entries of the table by address
MAX_LINES:      equ     3000            ; lines that have code
MAX_LABELS:     equ     300
MAX_FILES:      equ     16
MAX_SEGMENTS:   equ     64
BLOB_MAX:       equ     16              ; records of the index that NSADB takes
LINE_MAX:       equ     200
MAX_SEQUENCE:   equ     60000
TEXT_MAX:       equ     120
NAME_MAX:       equ     29
FILE_SIZE:      equ     16              ; name (12), lines, first key
SEG_SIZE:       equ     6               ; first sequence number, lines before, file, 0
LABEL_SIZE:     equ     32              ; name (29), segment, address

        org     0100h
start:  ld      (orig_sp),sp
        ld      sp,stack_top
        ld      hl,vars
        ld      de,vars+1
        ld      bc,vars_end-vars-1
        ld      (hl),0
        ldir
        call    main
exit:   ld      sp,(orig_sp)
        ret

main:   call    args_init
main_word:
        call    next_word
        jr      c,main_name
        ld      a,(word)
        cp      '-'
        jr      nz,main_file
        ld      a,(word+1)
        cp      'B'
        jr      z,option_b
        cp      'D'
        jr      nz,usage
        call    option_value
        jr      c,usage
        ld      (opt_dbase),de
        ld      a,1
        ld      (opt_has_dbase),a
        jr      main_word
option_b:
        call    option_value
        jr      c,usage
        ld      (opt_base),de
        ld      a,1
        ld      (opt_has_base),a
        jr      main_word
main_file:
        ld      a,(have_name)
        or      a
        jr      nz,usage
        inc     a
        ld      (have_name),a
        ld      hl,word
        ld      de,name_fcb
        call    parse_fcb
        ld      hl,name_fcb+1
        ld      b,8
name_check:
        ld      a,(hl)
        cp      '?'
        jr      z,usage
        inc     hl
        djnz    name_check
        jr      main_word
main_name:
        ld      a,(have_name)
        or      a
        jr      nz,run
usage:  ld      de,msg_usage
        jp      print

tool_option:
        scf
        ret

; The next word is a hexadecimal number: DE. Carry when there is none or it is not one.
option_value:
        call    next_word
        ret     c
        ld      hl,word
; HL = text of one to four hexadecimal digits: DE has them. Carry when it is not that.
parse_hex:
        ld      de,0
        ld      b,0
hex_next:
        ld      a,(hl)
        or      a
        jr      z,hex_end
        call    hex_digit
        jr      c,hex_bad
        ld      c,a
        inc     b
        ld      a,b
        cp      5
        jr      nc,hex_bad
        push    hl
        ex      de,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      a,l
        or      c
        ld      l,a
        ex      de,hl
        pop     hl
        inc     hl
        jr      hex_next
hex_end:
        ld      a,b
        or      a
        ret     nz
hex_bad:
        scf
        ret

; A = a character: its value, or carry when it is not a hexadecimal digit.
hex_digit:
        sub     '0'
        cp      10
        jr      nc,hex_letter
        or      a
        ret
hex_letter:
        sub     'A'-'0'
        cp      6
        jr      nc,hex_digit_bad
        add     a,10
        or      a
        ret
hex_digit_bad:
        scf
        ret

; ---------- the files ----------
run:    ld      a,1
        ld      (file_count),a
        ld      de,prn_rd
        ld      hl,ext_prn
        call    set_fcb
        ld      de,com_fcb
        ld      hl,ext_com
        call    set_fcb
        ld      de,dbg_wr
        ld      hl,ext_dbg
        call    set_fcb
        ld      de,tmp_rd
        ld      hl,ext_tmp
        call    set_fcb
        ld      de,tmp_wr
        ld      hl,ext_tmp
        call    set_fcb
        ld      hl,tmp_name
        ld      de,tmp_wr+1
        ld      bc,8
        ldir
        ld      hl,tmp_name
        ld      de,tmp_rd+1
        ld      bc,8
        ldir
        call    main_file_name
        ld      de,com_fcb
        ld      c,15
        call    BDOS
        inc     a
        ld      de,msg_no_com
        jp      z,fatal
        ld      de,com_fcb
        ld      c,35
        call    BDOS
        ld      hl,(com_fcb+33)
        ld      (prog_records),hl
        ld      de,hdrbuf
        ld      c,26
        call    BDOS
        ld      de,com_fcb
        ld      c,20
        call    BDOS
        or      a
        jr      nz,com_no_head
        ld      hl,hdrbuf
        ld      de,com_head
        ld      bc,3
        ldir
com_no_head:
        ld      ix,prn_rd
        call    rd_open
        ld      de,msg_no_prn
        jp      c,fatal
        ld      de,tmp_wr
        ld      c,19
        call    BDOS
        ld      ix,tmp_wr
        call    wr_create
        ld      de,msg_directory
        jp      c,fatal
        call    pass_listing
        ld      a,(listing_done)
        or      a
        ld      de,msg_incomplete
        jp      z,fatal
        ld      ix,tmp_wr
        call    wr_close
        ld      de,msg_full
        jp      c,fatal
        call    resolve_layout
        call    compute_bases
        call    convert_keys
        call    compact_entries
        call    build_lines
        call    sort_label_addresses
        call    layout
        call    write_dbg
        call    write_head
        ld      de,tmp_wr
        ld      c,19
        call    BDOS
        jp      report

; DE = an FCB, HL = the type (3 characters): the drive and the name of the program, the
; type, and the rest zero.
set_fcb:
        push    de
        push    hl
        ld      hl,name_fcb
        ld      bc,9
        ldir
        pop     hl
        ld      bc,3
        ldir
        pop     ix
        jp      fcb_clear_tail

; The name of the first file of the source: the name of the program and .MAC.
main_file_name:
        ld      hl,files
        ld      de,files+1
        ld      bc,11
        ld      (hl),' '
        ldir
        ld      hl,name_fcb+1
        ld      de,files
        ld      b,8
name_copy:
        ld      a,(hl)
        cp      ' '
        jr      z,name_type
        ld      (de),a
        inc     hl
        inc     de
        djnz    name_copy
name_type:
        ld      hl,text_mac
        ld      bc,4
        ldir
        ret

; DE = a message ended by $: show it and stop; the temporary file and an unfinished debug
; file are erased.
fatal:  call    print
abort:  ld      de,tmp_wr
        ld      c,19
        call    BDOS
        ld      a,(dbg_started)
        or      a
        jp      z,exit
        ld      de,dbg_wr
        ld      c,19
        call    BDOS
        jp      exit

; ---------- reading the listing ----------
pass_listing:
        ld      ix,prn_rd
        ld      de,linebuf
        ld      b,LINE_MAX
        call    rd_line
        ret     c
        call    row
        ld      a,(listing_done)
        or      a
        jr      z,pass_listing
        ret

; The line of the listing at linebuf. A page begins with a line that starts with a form
; feed, and two empty lines; the page of the symbols ends the listing. The other lines
; have 32 columns before the source: the address (2-5), the segment (6), the bytes (10-24),
; a flag of the file (25: C for a line of an included file) and one of the macros (26: +).
row:    ld      a,(linebuf)
        cp      0Ch
        jr      nz,row_body
        ld      hl,linebuf
header_end:
        ld      a,(hl)
        or      a
        jr      z,header_last
        inc     hl
        jr      header_end
header_last:
        dec     hl
        ld      a,(hl)
        cp      'S'
        jr      nz,header_page
        dec     hl
        ld      a,(hl)
        cp      9
        jr      nz,header_page
        ld      a,1
        ld      (listing_done),a
        ret
header_page:
        ld      a,2
        ld      (skip_lines),a
        ret
row_body:
        ld      a,(skip_lines)
        or      a
        jr      z,row_parse
        dec     a
        ld      (skip_lines),a
        ret
row_parse:
        call    pad_line
        call    row_fields
        call    trim_text
        xor     a
        ld      (row_is_code),a
        ld      a,(row_marker)
        cp      ' '
        jr      z,row_code
        cp      27h
        jr      nz,row_segment
row_code:
        ld      a,1
        ld      (row_is_code),a
row_segment:
        ld      hl,(row_addr)
        ld      de,(row_length)
        add     hl,de
        ld      (row_end),hl
        ld      a,(linebuf+26)
        cp      '+'
        jr      nz,row_not_macro
        call    row_has_code
        ret     z
        call    note_segment
        ld      hl,(row_addr)
        ld      de,(last_sequence)
        call    entry_put
        ld      hl,(row_end)
        ld      de,0
        jp      entry_put
row_not_macro:
        ld      hl,(row_length)
        ld      a,h
        or      l
        jr      z,row_source
        ld      a,(text_length)
        or      a
        jr      nz,row_source
        ld      a,(row_is_code)
        or      a
        ret     z
        call    note_segment
        ld      hl,(row_end)
        ld      de,0
        jp      entry_put
row_source:
        call    choose_file
        call    add_line
        call    write_text
        call    note_end
        call    row_has_code
        jr      z,row_label
        call    note_segment
        call    is_data
        ld      de,0
        jr      z,row_key
        ld      de,(last_sequence)
row_key:
        ld      hl,(row_addr)
        call    entry_put
        ld      hl,(row_end)
        ld      de,0
        call    entry_put
row_label:
        ld      a,(row_has_addr)
        or      a
        ret     z
        ld      a,(row_marker)
        cp      27h
        jr      z,row_label_ok
        cp      ' '
        jr      z,row_label_ok
        cp      '"'
        ret     nz
row_label_ok:
        jp      label_check

; The row has code: the program has code in the absolute segment (ASEG) or in the relocatable
; one (CSEG), which is where the addresses have to be moved.
note_segment:
        ld      a,(row_marker)
        cp      27h
        jr      z,note_relocatable
        ld      a,1
        ld      (seen_absolute),a
        ret
note_relocatable:
        ld      a,1
        ld      (seen_relocatable),a
        ret

; The name that END has (the start of the program), if it has one.
note_end:
        ld      hl,linebuf+32
        call    statement_start
        call    read_word
        ld      de,words_end
        call    in_table
        ret     nz
        call    skip_white
        call    name_start
        ret     c
        ld      de,end_name
        call    read_name
        ld      a,1
        ld      (have_end),a
        ret

; Z when the row has no bytes of code: it is not in the code, or it has no bytes.
row_has_code:
        ld      a,(row_is_code)
        or      a
        ret     z
        ld      hl,(row_length)
        ld      a,h
        or      l
        ret

; The line has at least 32 characters.
pad_line:
        ld      hl,linebuf
        ld      b,32
pad_next:
        ld      a,(hl)
        or      a
        jr      z,pad_fill
        inc     hl
        djnz    pad_next
        ret
pad_fill:
        ld      (hl),' '
        inc     hl
        djnz    pad_fill
        ld      (hl),0
        ret

; The fields of the row: the address, if it has one, the segment mark and the number of
; bytes of code.
row_fields:
        ld      a,(linebuf+6)
        ld      (row_marker),a
        xor     a
        ld      (row_has_addr),a
        ld      hl,0
        ld      (row_addr),hl
        ld      (row_length),hl
        ld      hl,linebuf+2
        ld      b,4
        ld      de,0
field_digit:
        ld      a,(hl)
        call    hex_digit
        ret     c
        push    hl
        ex      de,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      c,a
        ld      a,l
        or      c
        ld      l,a
        ex      de,hl
        pop     hl
        inc     hl
        djnz    field_digit
        ld      (row_addr),de
        ld      a,1
        ld      (row_has_addr),a
        ld      a,(linebuf+10)
        cp      ' '
        ret     z
        ld      hl,linebuf+10
        ld      b,15
        ld      c,0
field_byte:
        ld      a,(hl)
        inc     hl
        push    bc
        call    hex_digit
        pop     bc
        jr      c,field_next
        inc     c
field_next:
        djnz    field_byte
        srl     c
        ld      b,0
        ld      (row_length),bc
        ret

; The source of the row ends at its last character that is not a blank or a control; its
; length is kept (0 for an empty line).
trim_text:
        ld      hl,linebuf+32
trim_end:
        ld      a,(hl)
        or      a
        jr      z,trim_back
        inc     hl
        jr      trim_end
trim_back:
        ld      de,linebuf+32
        or      a
        sbc     hl,de
        add     hl,de
        jr      z,trim_done
        dec     hl
        ld      a,(hl)
        cp      ' '+1
        jr      c,trim_back
        inc     hl
trim_done:
        ld      (hl),0
        or      a
        sbc     hl,de
        ld      a,l
        ld      (text_length),a
        ret

; ---------- the files of the source ----------
; The file of a source line goes to `line_file`. The lines of an included file have a C in
; the flag of the file, and so has the INCLUDE line, which is a line of the file that has it:
; the file of the include is made at its first line.
choose_file:
        ld      a,(linebuf+25)
        cp      'C'
        jr      nz,file_main
        call    is_include
        jr      z,file_lines
        ld      a,1
        ld      (include_state),a
        jr      file_zero
file_lines:
        ld      a,(include_state)
        or      a
        jr      z,file_main
        cp      1
        jr      nz,file_inside
        ld      a,(file_count)
        cp      MAX_FILES
        ld      de,msg_files
        jp      nc,fatal
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,files
        add     hl,de
        ex      de,hl
        ld      hl,include_name
        ld      bc,12
        ldir
        ld      a,(file_count)
        ld      (include_file),a
        inc     a
        ld      (file_count),a
        ld      a,2
        ld      (include_state),a
file_inside:
        ld      a,(include_file)
        ld      (line_file),a
        ret
file_main:
        xor     a
        ld      (include_state),a
file_zero:
        xor     a
        ld      (line_file),a
        ret

; The line is the next one of its file: the sequence number goes up, and a new segment
; starts when the file changes (the segments turn a sequence number into the key).
add_line:
        ld      hl,(last_sequence)
        inc     hl
        ld      (last_sequence),hl
        ld      de,MAX_SEQUENCE+1
        or      a
        sbc     hl,de
        ld      de,msg_lines
        jp      nc,fatal
        ld      a,(line_file)
        call    file_entry
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (lines_before),de
        inc     de
        ld      (hl),d
        dec     hl
        ld      (hl),e
        ld      a,(segment_count)
        or      a
        jr      z,segment_new
        dec     a
        call    segment_entry
        ld      de,4
        add     hl,de
        ld      a,(line_file)
        cp      (hl)
        ret     z
segment_new:
        ld      a,(segment_count)
        cp      MAX_SEGMENTS
        ld      de,msg_segments
        jp      nc,fatal
        call    segment_entry
        ld      de,(last_sequence)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      de,(lines_before)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      a,(line_file)
        ld      (hl),a
        ld      hl,segment_count
        inc     (hl)
        ret

; A = a file: HL = the address of the word of its lines, in the table of the files.
file_entry:
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,files+12
        add     hl,de
        ret

; A = a segment: HL = its entry.
segment_entry:
        ld      l,a
        ld      h,0
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,de
        add     hl,hl
        ld      de,segments
        add     hl,de
        ret

; An INCLUDE statement ([label:] [$|.]INCLUDE [d:]name): Z when the source is not one; if
; it is, include_name has the name in capitals (12 characters, blanks after).
is_include:
        ld      hl,linebuf+32
        call    statement_start
        ld      a,(hl)
        cp      '$'
        jr      z,include_dot
        cp      '.'
        jr      nz,include_word
include_dot:
        inc     hl
include_word:
        call    read_word
        ld      de,word_include
        call    in_table
        jr      nz,include_no
        ld      a,(hl)
        cp      ' '
        jr      z,include_blank
        cp      9
        jr      nz,include_no
include_blank:
        call    skip_white
        ld      a,(hl)
        call    upper
        cp      'A'
        jr      c,include_name_start
        cp      'P'+1
        jr      nc,include_name_start
        inc     hl
        ld      a,(hl)
        dec     hl
        cp      ':'
        jr      nz,include_name_start
        inc     hl
        inc     hl
include_name_start:
        ld      de,include_name
        ld      b,12
include_copy:
        ld      a,(hl)
        cp      ' '+1
        jr      c,include_fill
        cp      ';'
        jr      z,include_fill
        inc     hl
        call    upper
        ld      (de),a
        inc     de
        djnz    include_copy
        jr      include_yes
include_fill:
        ld      a,' '
include_pad:
        ld      (de),a
        inc     de
        djnz    include_pad
include_yes:
        ld      a,1
        or      a
        ret
include_no:
        xor     a
        ret

; ---------- the text of the source ----------
; The text of the row (tabs to the next multiple of 4, other controls as ?, at most 120
; columns, no blanks at the end) goes to the temporary file with the file of the line before
; it and a carriage return after it.
write_text:
        ld      hl,linebuf+32
        ld      de,textbuf
        ld      b,0
text_next:
        ld      a,(hl)
        or      a
        jr      z,text_done
        inc     hl
        cp      9
        jr      z,text_tab
        cp      ' '
        jr      c,text_control
        cp      7Fh
        jr      c,text_put
text_control:
        ld      a,'?'
text_put:
        ld      c,a
        ld      a,b
        cp      TEXT_MAX
        jr      nc,text_done
        ld      a,c
        ld      (de),a
        inc     de
        inc     b
        jr      text_next
text_tab:
        ld      a,b
        and     3
        ld      c,a
        ld      a,4
        sub     c
        ld      c,a
text_spaces:
        ld      a,b
        cp      TEXT_MAX
        jr      nc,text_done
        ld      a,' '
        ld      (de),a
        inc     de
        inc     b
        dec     c
        jr      nz,text_spaces
        jr      text_next
text_done:
        ld      hl,textbuf
text_trim:
        or      a
        sbc     hl,de
        add     hl,de
        jr      z,text_out
        dec     de
        ld      a,(de)
        cp      ' '
        jr      z,text_trim
        inc     de
text_out:
        ex      de,hl
        ld      (hl),0Dh
        inc     hl
        ld      de,textbuf
        or      a
        sbc     hl,de
        ld      (text_count),hl
        ld      a,(line_file)
        ld      ix,tmp_wr
        call    wr_putc
        ld      de,msg_full
        jp      c,fatal
        ld      hl,textbuf
text_write:
        ld      bc,(text_count)
        ld      a,b
        or      c
        ret     z
        dec     bc
        ld      (text_count),bc
        ld      a,(hl)
        inc     hl
        ld      (text_pointer),hl
        ld      ix,tmp_wr
        call    wr_putc
        ld      de,msg_full
        jp      c,fatal
        ld      hl,(text_pointer)
        jr      text_write

; ---------- the kinds of statements ----------
; Z when the source is a DB, DW, DC, DS or one of their DEF forms, after an optional label.
is_data:
        ld      hl,linebuf+32
        call    statement_start
        call    read_word
        ld      de,words_data
; Z when the word that was read is one of the words at DE (each ended by zero, the table
; by a second zero). HL is kept.
in_table:
        ld      a,(de)
        or      a
        jr      z,in_table_no
        push    hl
        ld      hl,word_buffer
in_table_compare:
        ld      a,(de)
        cp      (hl)
        jr      nz,in_table_skip
        inc     de
        inc     hl
        or      a
        jr      nz,in_table_compare
        pop     hl
        xor     a
        ret
in_table_skip:
        ld      a,(de)
        inc     de
        or      a
        jr      nz,in_table_skip
        pop     hl
        jr      in_table
in_table_no:
        ld      a,1
        or      a
        ret

; HL = a text: the word that it has (letters, digits and _ . $ @ ?, in capitals, at most 15
; characters) goes to word_buffer; HL is after it.
read_word:
        ld      de,word_buffer
        ld      c,15
read_next:
        ld      a,(hl)
        call    is_word
        jr      nc,read_end
        inc     hl
        ld      b,a
        ld      a,c
        or      a
        jr      z,read_next
        ld      a,b
        call    upper
        ld      (de),a
        inc     de
        dec     c
        jr      read_next
read_end:
        xor     a
        ld      (de),a
        ret

; HL = a text: the statement after the blanks and an optional label (name:), and the
; blanks after the label.
statement_start:
        call    skip_white
        ld      (statement_text),hl
statement_scan:
        ld      a,(hl)
        call    is_word
        jr      nc,statement_stop
        inc     hl
        jr      statement_scan
statement_stop:
        ld      a,(hl)
        cp      ':'
        jr      nz,statement_plain
        ld      de,(statement_text)
        or      a
        sbc     hl,de
        add     hl,de
        jr      z,statement_plain
        inc     hl
        ld      a,(hl)
        cp      ':'
        jr      nz,statement_blank
        inc     hl
statement_blank:
        jr      skip_white
statement_plain:
        ld      hl,(statement_text)
        ret

skip_white:
        ld      a,(hl)
        cp      ' '
        jr      z,white_next
        cp      9
        ret     nz
white_next:
        inc     hl
        jr      skip_white

; Carry when A is a letter, a digit or one of _ . $ @ ?
is_word:
        cp      '0'
        jr      c,word_punct
        cp      '9'+1
        jr      c,word_yes
        cp      'A'
        jr      c,word_punct
        cp      'Z'+1
        jr      c,word_yes
        cp      '_'
        jr      z,word_yes
        cp      'a'
        jr      c,word_no
        cp      'z'+1
        jr      c,word_yes
word_no:
        or      a
        ret
word_punct:
        cp      '.'
        jr      z,word_yes
        cp      '$'
        jr      z,word_yes
        cp      '?'
        jr      z,word_yes
        cp      '@'
        jr      nz,word_no
word_yes:
        scf
        ret

; A in capitals.
upper:
        cp      'a'
        ret     c
        cp      'z'+1
        ret     nc
        sub     20h
        ret

words_data:     defm    "DB",0,"DW",0,"DC",0,"DS",0,"DEFB",0,"DEFW",0,"DEFS",0,"DEFM",0,"DEFC",0,0
words_not_label: defm   "EQU",0,"DEFL",0,"SET",0,"MACRO",0,0
word_include:   defm    "INCLUDE",0,"MACLIB",0,0
words_end:      defm    "END",0,0

; ---------- the labels ----------
; A label is a name at the start of the source with a colon (two for a public one) that is
; not the name of a constant: NAME: EQU, DEFL, SET, = or MACRO. Its address is the one of
; the row.
label_check:
        ld      hl,linebuf+32
        call    skip_white
        call    name_start
        ret     c
        ld      de,name_buffer
        call    read_name
label_colon:
        ld      a,(hl)
        cp      ':'
        ret     nz
        inc     hl
        ld      a,(hl)
        cp      ':'
        jr      nz,label_rest
        inc     hl
label_rest:
        call    skip_white
        ld      a,(hl)
        cp      '='
        ret     z
        call    read_word
        ld      de,words_not_label
        call    in_table
        ret     z
        jp      label_put

; HL = a text: carry when it does not start a name (a letter, _ or .).
name_start:
        ld      a,(hl)
        cp      '_'
        ret     z
        cp      '.'
        ret     z
        call    upper
        cp      'A'
        ret     c
        cp      'Z'+1
        ccf
        ret

; HL = a name, DE = 29 bytes: the name in capitals, cut at 29 characters, and zero after it.
read_name:
        ld      b,NAME_MAX
name_clear:
        xor     a
        ld      (de),a
        inc     de
        djnz    name_clear
        ld      a,e
        sub     NAME_MAX
        ld      e,a
        jr      nc,name_copy_start
        dec     d
name_copy_start:
        ld      c,0
name_copy_next:
        ld      a,(hl)
        call    is_word
        ret     nc
        ld      a,(hl)
        inc     hl
        ld      b,a
        ld      a,c
        cp      NAME_MAX
        jr      nc,name_copy_next
        ld      a,b
        call    upper
        ld      (de),a
        inc     de
        inc     c
        jr      name_copy_next

; The label in name_buffer: Z when it is in the table (HL = its entry); if not, search_low
; is the place where it goes.
label_lookup:
        ld      hl,0
        ld      (search_low),hl
        ld      hl,(label_count)
        ld      (search_high),hl
label_search:
        ld      hl,(search_high)
        ld      de,(search_low)
        or      a
        sbc     hl,de
        jr      z,label_none
        srl     h
        rr      l
        add     hl,de
        ld      (search_mid),hl
        call    label_pointer_at
        ld      (found_pointer),hl
        ld      de,name_buffer
        ld      b,NAME_MAX
label_compare:
        ld      a,(de)
        cp      (hl)
        jr      nz,label_differs
        inc     hl
        inc     de
        djnz    label_compare
        ld      hl,(found_pointer)
        xor     a
        ret
label_differs:
        ld      hl,(search_mid)
        jr      c,label_below
        inc     hl
        ld      (search_low),hl
        jr      label_search
label_below:
        ld      (search_high),hl
        jr      label_search
label_none:
        ld      a,1
        or      a
        ret

; The label in name_buffer, with the segment of the row and its address, goes into the table
; in the order of the names. A name that is there is not kept (a count is shown).
label_put:
        call    label_lookup
        jr      nz,label_insert
        ld      hl,(duplicates)
        inc     hl
        ld      (duplicates),hl
        ret
label_insert:
        ld      hl,(label_count)
        ld      de,MAX_LABELS
        or      a
        sbc     hl,de
        ld      de,msg_labels
        jp      nc,fatal
        ld      hl,(label_count)
        ld      de,(search_low)
        or      a
        sbc     hl,de
        jr      z,label_write
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      b,h
        ld      c,l
        ld      hl,(label_count)
        call    label_pointer_at
        dec     hl
        ld      d,h
        ld      e,l
        ld      a,e
        add     a,LABEL_SIZE
        ld      e,a
        jr      nc,label_move
        inc     d
label_move:
        lddr
label_write:
        ld      hl,(search_low)
        call    label_pointer_at
        ex      de,hl
        ld      hl,name_buffer
        ld      bc,NAME_MAX
        ldir
        xor     a
        ld      (de),a
        ld      a,(row_marker)
        cp      '"'
        jr      nz,label_code
        ld      a,1
        ld      (de),a
        jr      label_segment
label_code:
        cp      27h
        jr      nz,label_segment
        ld      a,2
        ld      (de),a
label_segment:
        inc     de
        ld      hl,(row_addr)
        ex      de,hl
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ld      hl,(label_count)
        inc     hl
        ld      (label_count),hl
        ret

; HL = the number of a label: HL = its entry.
label_pointer_at:
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,labels
        add     hl,de
        ret

; ---------- the tables of entries ----------
; HL = an address, DE = a key (a sequence number, 0 for data or the end of the code): put it
; in the table by address, which stays in the order of the addresses. An address that is
; there keeps its key, unless the new key is not 0.
entry_put:
        ld      (put_address),hl
        ld      (put_key),de
        ld      iy,entries
        ld      hl,(entry_count)
        ld      de,(put_address)
        call    table_search
        jr      nz,entry_new
        ld      de,(put_key)
        ld      a,d
        or      e
        ret     z
        call    table_pointer
        inc     hl
        inc     hl
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ret
entry_new:
        ld      hl,(entry_count)
        ld      de,MAX_ENTRIES
        or      a
        sbc     hl,de
        ld      de,msg_entries
        jp      nc,fatal
        ld      hl,(put_address)
        ld      (insert_first),hl
        ld      hl,(put_key)
        ld      (insert_second),hl
        ld      hl,entry_count
        jp      table_insert

; A table of entries of two words (4 bytes) in the order of the first. IY = the table,
; HL = the number of entries, DE = a value: BC = the number of the first entry that is not
; less than it; Z when that entry has the value.
table_search:
        ld      (search_value),de
        ld      (search_count),hl
        ld      (search_high),hl
        ld      bc,0
search_loop:
        ld      hl,(search_high)
        or      a
        sbc     hl,bc
        jr      z,search_done
        srl     h
        rr      l
        add     hl,bc
        push    hl
        add     hl,hl
        add     hl,hl
        push    iy
        pop     de
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      hl,(search_value)
        ex      de,hl
        or      a
        sbc     hl,de
        pop     hl
        jr      nc,search_below
        inc     hl
        ld      b,h
        ld      c,l
        jr      search_loop
search_below:
        ld      (search_high),hl
        jr      search_loop
search_done:
        ld      hl,(search_count)
        or      a
        sbc     hl,bc
        jr      z,search_none
        call    table_pointer
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      hl,(search_value)
        or      a
        sbc     hl,de
        ret
search_none:
        ld      a,1
        or      a
        ret

; IY = a table, BC = an entry: HL = its address. (DE is kept.)
table_pointer:
        push    de
        ld      h,b
        ld      l,c
        add     hl,hl
        add     hl,hl
        push    iy
        pop     de
        add     hl,de
        pop     de
        ret

; The entry (insert_first, insert_second) goes into the table IY at the place BC; HL = the
; word that has the number of entries, which goes up by one.
table_insert:
        ld      (insert_count_pointer),hl
        ld      (insert_place),bc
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (insert_count),de
        ex      de,hl
        or      a
        sbc     hl,bc
        jr      z,insert_write
        add     hl,hl
        add     hl,hl
        ld      b,h
        ld      c,l
        ld      hl,(insert_count)
        add     hl,hl
        add     hl,hl
        push    iy
        pop     de
        add     hl,de
        dec     hl
        ld      d,h
        ld      e,l
        inc     de
        inc     de
        inc     de
        inc     de
        lddr
insert_write:
        ld      bc,(insert_place)
        call    table_pointer
        ld      de,(insert_first)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      de,(insert_second)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ld      hl,(insert_count_pointer)
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     de
        ld      (hl),d
        dec     hl
        ld      (hl),e
        ret

; ---------- after the listing ----------
; The first key of each file (the lines of the files follow each other, from 1) and the
; number of lines.
compute_bases:
        ld      hl,1
        ld      a,(file_count)
        ld      b,a
        ld      ix,files
        ld      de,FILE_SIZE
bases_next:
        ld      (ix+14),l
        ld      (ix+15),h
        ld      c,(ix+12)
        push    bc
        ld      b,(ix+13)
        add     hl,bc
        pop     bc
        jr      c,bases_overflow
        add     ix,de
        djnz    bases_next
        dec     hl
        ld      (total_lines),hl
        ret
bases_overflow:
        ld      de,msg_lines
        jp      fatal

; Each sequence number in the table by address becomes its key.
convert_keys:
        ld      hl,(entry_count)
        ld      (work_count),hl
        ld      iy,entries
convert_next:
        ld      hl,(work_count)
        ld      a,h
        or      l
        ret     z
        dec     hl
        ld      (work_count),hl
        ld      e,(iy+2)
        ld      d,(iy+3)
        ld      a,d
        or      e
        jr      z,convert_skip
        call    sequence_key
        ld      (iy+2),e
        ld      (iy+3),d
convert_skip:
        ld      bc,4
        add     iy,bc
        jr      convert_next

; DE = a sequence number: DE = its key, which is the first key of its file, plus the lines
; of the file before its segment, plus its place in the segment.
sequence_key:
        ld      (key_sequence),de
        ld      ix,segments
        ld      a,(segment_count)
        ld      b,a
key_search:
        ld      a,b
        cp      1
        jr      z,key_found
        ld      e,(ix+SEG_SIZE)
        ld      d,(ix+SEG_SIZE+1)
        ld      hl,(key_sequence)
        or      a
        sbc     hl,de
        jr      c,key_found
        ld      de,SEG_SIZE
        add     ix,de
        djnz    key_search
key_found:
        ld      e,(ix+0)
        ld      d,(ix+1)
        ld      hl,(key_sequence)
        or      a
        sbc     hl,de
        ld      e,(ix+2)
        ld      d,(ix+3)
        add     hl,de
        ld      a,(ix+4)
        push    hl
        call    file_entry
        ld      de,2
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        pop     hl
        add     hl,de
        ex      de,hl
        ret

; The entries that follow an entry without key, and have none, are left out.
compact_entries:
        ld      hl,(entry_count)
        ld      (work_count),hl
        ld      hl,0
        ld      (kept_count),hl
        xor     a
        ld      (previous_zero),a
        ld      hl,entries
        ld      de,entries
compact_next:
        push    hl
        ld      hl,(work_count)
        ld      a,h
        or      l
        jr      z,compact_end
        dec     hl
        ld      (work_count),hl
        pop     hl
        inc     hl
        inc     hl
        ld      a,(hl)
        inc     hl
        or      (hl)
        dec     hl
        dec     hl
        dec     hl
        jr      nz,compact_keep
        ld      a,(previous_zero)
        or      a
        jr      z,compact_zero
        inc     hl
        inc     hl
        inc     hl
        inc     hl
        jr      compact_next
compact_zero:
        ld      a,1
        ld      (previous_zero),a
        jr      compact_copy
compact_keep:
        xor     a
        ld      (previous_zero),a
compact_copy:
        ld      bc,4
        ldir
        push    hl
        ld      hl,(kept_count)
        inc     hl
        ld      (kept_count),hl
        pop     hl
        jr      compact_next
compact_end:
        pop     hl
        ld      hl,(kept_count)
        ld      (entry_count),hl
        ret

; The table by line: (key, address) for the first address of each line that has code.
build_lines:
        ld      hl,entries
        ld      (read_pointer),hl
        ld      hl,(entry_count)
        ld      (work_count),hl
build_next:
        ld      hl,(work_count)
        ld      a,h
        or      l
        ret     z
        dec     hl
        ld      (work_count),hl
        ld      hl,(read_pointer)
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        ld      (read_pointer),hl
        ld      a,b
        or      c
        jr      z,build_next
        ld      (line_address),de
        ld      (line_key),bc
        ld      iy,lines_tab
        ld      hl,(line_count)
        ld      d,b
        ld      e,c
        call    table_search
        jr      z,build_next
        ld      hl,(line_count)
        ld      de,MAX_LINES
        or      a
        sbc     hl,de
        ld      de,msg_line_table
        jp      nc,fatal
        ld      hl,(line_key)
        ld      (insert_first),hl
        ld      hl,(line_address)
        ld      (insert_second),hl
        ld      hl,line_count
        call    table_insert
        jr      build_next

; Where the segments are. A program with code in ASEG has its final addresses. A program with
; CSEG has them relative: the code goes to the address of -b or, as L80 makes the COM file, to
; where its first three bytes (JP) send it, minus the place of the label of END; the data segment
; goes to the address of -d, or 0103h (after the JP). The addresses of the table and of the
; labels are moved.
resolve_layout:
        ld      a,(seen_absolute)
        ld      hl,seen_relocatable
        and     (hl)
        ld      de,msg_mixed
        jp      nz,fatal
        ld      hl,(opt_base)
        ld      a,(opt_has_base)
        or      a
        jr      nz,layout_base
        ld      hl,0100h
        ld      a,(com_head)
        cp      0C3h
        jr      nz,layout_base
        ld      a,(have_end)
        or      a
        jr      z,layout_base
        ld      hl,end_name
        ld      de,name_buffer
        ld      bc,NAME_MAX
        ldir
        call    label_lookup
        jr      nz,layout_default
        push    hl
        pop     ix
        ld      a,(ix+29)
        cp      2
        jr      nz,layout_default
        ld      e,(ix+30)
        ld      d,(ix+31)
        ld      hl,(com_head+1)
        or      a
        sbc     hl,de
        jr      layout_base
layout_default:
        ld      hl,0100h
layout_base:
        ld      (base_final),hl
        ld      hl,(opt_dbase)
        ld      a,(opt_has_dbase)
        or      a
        jr      nz,layout_data
        ld      hl,0103h
layout_data:
        ld      (data_base),hl
        ld      a,(seen_relocatable)
        or      a
        jr      z,fix_labels
        ld      hl,(entry_count)
        ld      (work_count),hl
        ld      iy,entries
        ld      de,(base_final)
move_next:
        ld      hl,(work_count)
        ld      a,h
        or      l
        jr      z,fix_labels
        dec     hl
        ld      (work_count),hl
        ld      l,(iy+0)
        ld      h,(iy+1)
        add     hl,de
        ld      de,msg_wrap
        jp      c,fatal
        ld      de,(base_final)
        ld      (iy+0),l
        ld      (iy+1),h
        ld      bc,4
        add     iy,bc
        jr      move_next

; The labels of the code and of the data segment get their addresses.
fix_labels:
        ld      hl,(label_count)
        ld      (work_count),hl
        ld      ix,labels
fix_next:
        ld      hl,(work_count)
        ld      a,h
        or      l
        ret     z
        dec     hl
        ld      (work_count),hl
        ld      a,(ix+29)
        ld      (ix+29),0
        or      a
        jr      z,fix_skip
        ld      de,(base_final)
        cp      2
        jr      z,fix_add
        ld      de,(data_base)
fix_add:
        ld      l,(ix+30)
        ld      h,(ix+31)
        add     hl,de
        ld      (ix+30),l
        ld      (ix+31),h
fix_skip:
        ld      de,LABEL_SIZE
        add     ix,de
        jr      fix_next

; label_order has the numbers of the labels in the order of their addresses (the order of
; the names for the same address), made by insertion.
sort_label_addresses:
        ld      hl,0
        ld      (sort_i),hl
sort_outer:
        ld      hl,(sort_i)
        ld      de,(label_count)
        or      a
        sbc     hl,de
        ret     nc
        ld      hl,(sort_i)
        call    label_address
        ld      (sort_address),hl
        ld      hl,(sort_i)
        ld      (sort_j),hl
sort_inner:
        ld      hl,(sort_j)
        ld      a,h
        or      l
        jr      z,sort_place
        dec     hl
        call    order_get
        call    label_address
        ex      de,hl
        ld      hl,(sort_address)
        or      a
        sbc     hl,de
        jr      nc,sort_place
        ld      hl,(sort_j)
        dec     hl
        call    order_get
        push    hl
        ld      hl,(sort_j)
        call    order_pointer
        pop     de
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ld      hl,(sort_j)
        dec     hl
        ld      (sort_j),hl
        jr      sort_inner
sort_place:
        ld      hl,(sort_j)
        call    order_pointer
        ld      de,(sort_i)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ld      hl,(sort_i)
        inc     hl
        ld      (sort_i),hl
        jr      sort_outer

; HL = the number of a label: HL = its address.
label_address:
        call    label_pointer_at
        ld      de,30
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ret

; HL = a place in label_order: HL = its address.
order_pointer:
        add     hl,hl
        ld      de,label_order
        add     hl,de
        ret

; HL = a place in label_order: HL = the number of the label there.
order_get:
        call    order_pointer
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ret

; ---------- the layout of the file ----------
; Sizes of the parts, and the header and the index (the lines of the text are put in the
; index when the text is written).
layout:
        ld      hl,(entry_count)
        ld      de,31
        add     hl,de
        call    shift_five
        ld      (addr_records),hl
        ld      hl,(line_count)
        ld      de,31
        add     hl,de
        call    shift_five
        ld      (line_records),hl
        ld      hl,(label_count)
        ld      de,3
        add     hl,de
        srl     h
        rr      l
        srl     h
        rr      l
        ld      (symbol_records),hl
        ld      hl,(total_lines)
        ld      de,15
        add     hl,de
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        ld      (text_entries),hl
        ld      a,(file_count)
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      (off_addr),hl
        ld      de,(addr_records)
        add     hl,de
        add     hl,de
        ld      (off_line),hl
        ld      de,(line_records)
        add     hl,de
        add     hl,de
        ld      (off_symaddr),hl
        ld      de,(symbol_records)
        add     hl,de
        add     hl,de
        ld      (off_text),hl
        ld      de,(text_entries)
        add     hl,de
        add     hl,de
        add     hl,de
        ld      de,127
        add     hl,de
        add     hl,hl
        ld      l,h
        ld      h,0
        ld      a,l
        ld      (blob_records),a
        cp      BLOB_MAX+1
        ld      de,msg_index
        jp      nc,fatal
        ld      hl,1
        ld      a,(blob_records)
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (rec_addr),hl
        ld      de,(addr_records)
        add     hl,de
        ld      (rec_line),hl
        ld      de,(line_records)
        add     hl,de
        ld      (rec_symname),hl
        ld      de,(symbol_records)
        add     hl,de
        ld      (rec_symaddr),hl
        add     hl,de
        ld      (rec_text),hl
        jp      build_head

; HL shifted right five times.
shift_five:
        ld      b,5
shift_next:
        srl     h
        rr      l
        djnz    shift_next
        ret

; The header (record 0) and the part of the index that is known: the table of the files and
; the first word of each record of the tables.
build_head:
        ld      hl,hdrbuf
        ld      de,hdrbuf+1
        ld      bc,(BLOB_MAX+1)*128-1
        ld      (hl),0
        ldir
        ld      hl,hdrbuf
        ld      (hl),'N'
        inc     hl
        ld      (hl),'S'
        inc     hl
        ld      (hl),'D'
        inc     hl
        ld      (hl),'B'
        inc     hl
        ld      (hl),1
        inc     hl
        ld      a,(file_count)
        ld      (hl),a
        ld      hl,(entry_count)
        ld      (hdrbuf+6),hl
        ld      hl,(line_count)
        ld      (hdrbuf+8),hl
        ld      hl,(label_count)
        ld      (hdrbuf+10),hl
        ld      a,(blob_records)
        ld      (hdrbuf+12),a
        ld      hl,(rec_addr)
        ld      (hdrbuf+14),hl
        ld      hl,(rec_line)
        ld      (hdrbuf+16),hl
        ld      hl,(rec_symname)
        ld      (hdrbuf+18),hl
        ld      hl,(rec_symaddr)
        ld      (hdrbuf+20),hl
        ld      hl,(rec_text)
        ld      (hdrbuf+22),hl
        ld      hl,(off_addr)
        ld      (hdrbuf+26),hl
        ld      hl,(off_line)
        ld      (hdrbuf+28),hl
        ld      hl,(off_symaddr)
        ld      (hdrbuf+30),hl
        ld      hl,(off_text)
        ld      (hdrbuf+32),hl
        ld      hl,(prog_records)
        ld      (hdrbuf+34),hl
        ld      a,(file_count)
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      b,h
        ld      c,l
        ld      hl,files
        ld      de,hdrbuf+128
        ldir
        ld      hl,hdrbuf+128
        ld      de,(off_addr)
        add     hl,de
        ex      de,hl
        ld      hl,entries
        ld      bc,(addr_records)
        call    copy_firsts
        ld      hl,hdrbuf+128
        ld      de,(off_line)
        add     hl,de
        ex      de,hl
        ld      hl,lines_tab
        ld      bc,(line_records)
        call    copy_firsts
        ld      hl,0
        ld      (sort_i),hl
symbol_first:
        ld      hl,(sort_i)
        ld      de,(symbol_records)
        or      a
        sbc     hl,de
        ret     nc
        ld      hl,(sort_i)
        add     hl,hl
        add     hl,hl
        call    order_get
        call    label_address
        ex      de,hl
        ld      hl,(sort_i)
        add     hl,hl
        ld      bc,(off_symaddr)
        add     hl,bc
        ld      bc,hdrbuf+128
        add     hl,bc
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ld      hl,(sort_i)
        inc     hl
        ld      (sort_i),hl
        jr      symbol_first

; HL = a table of entries of 4 bytes, DE = where the words go, BC = how many: the first
; word of every 32nd entry.
copy_firsts:
        ld      a,b
        or      c
        ret     z
        ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        ld      a,(hl)
        ld      (de),a
        inc     de
        ld      a,127
        push    de
        ld      e,a
        ld      d,0
        add     hl,de
        pop     de
        dec     bc
        jr      copy_firsts

; ---------- writing the file ----------
; The file is made with room for the header and the index, which come last (they have the
; place of the text); then the tables, and the text.
write_dbg:
        ld      de,dbg_wr
        ld      c,19
        call    BDOS
        ld      ix,dbg_wr
        call    wr_create
        ld      de,msg_directory
        jp      c,fatal
        ld      a,1
        ld      (dbg_started),a
        ld      a,(blob_records)
        inc     a
        ld      h,a
        ld      l,0
        srl     h
        rr      l
        ld      b,h
        ld      c,l
zero_loop:
        ld      a,b
        or      c
        jr      z,zero_done
        dec     bc
        push    bc
        xor     a
        call    out_byte
        pop     bc
        jr      zero_loop
zero_done:
        ld      hl,entries
        ld      bc,(entry_count)
        call    out_entries
        ld      hl,lines_tab
        ld      bc,(line_count)
        call    out_entries
        ld      hl,0
        ld      (sort_i),hl
name_next:
        ld      hl,(sort_i)
        ld      de,(label_count)
        or      a
        sbc     hl,de
        jr      nc,names_done
        ld      hl,(sort_i)
        call    out_label
        ld      hl,(sort_i)
        inc     hl
        ld      (sort_i),hl
        jr      name_next
names_done:
        call    pad_record
        ld      hl,0
        ld      (sort_i),hl
order_next:
        ld      hl,(sort_i)
        ld      de,(label_count)
        or      a
        sbc     hl,de
        jr      nc,order_done
        ld      hl,(sort_i)
        call    order_get
        call    out_label
        ld      hl,(sort_i)
        inc     hl
        ld      (sort_i),hl
        jr      order_next
order_done:
        call    pad_record
        call    write_texts
        call    pad_record
        ld      ix,dbg_wr
        call    wr_close
        ld      de,msg_full
        jp      c,fatal
        ret

; HL = a table of entries of 4 bytes, BC = how many: the table, filled to a record.
out_entries:
        ld      (block_pointer),hl
        ld      h,b
        ld      l,c
        add     hl,hl
        add     hl,hl
        ld      (block_count),hl
        call    out_block
        jr      pad_record

; The bytes at block_pointer, as many as block_count.
out_block:
        ld      hl,(block_count)
        ld      a,h
        or      l
        ret     z
        dec     hl
        ld      (block_count),hl
        ld      hl,(block_pointer)
        ld      a,(hl)
        inc     hl
        ld      (block_pointer),hl
        call    out_byte
        jr      out_block

; HL = the number of a label: its name (29 characters), a zero and its address.
out_label:
        call    label_pointer_at
        ld      (block_pointer),hl
        ld      hl,NAME_MAX
        ld      (block_count),hl
        call    out_block
        xor     a
        call    out_byte
        ld      hl,(block_pointer)
        inc     hl
        ld      (block_pointer),hl
        ld      hl,2
        ld      (block_count),hl
        jr      out_block

; The byte A to the debug file.
out_byte:
        ld      ix,dbg_wr
        call    wr_putc
        ret     nc
        ld      de,msg_full
        jp      fatal

; The debug file is filled to a record with zeros.
pad_record:
        ld      a,(dbg_wr+W_POS)
        or      a
        ret     z
        xor     a
        call    out_byte
        jr      pad_record

; The text: one pass over the temporary file for each file of the source, which copies the
; lines of that file. The place of every 16th line (record and offset in the text) goes to
; the index.
write_texts:
        xor     a
        ld      (pass_file),a
text_pass:
        ld      ix,tmp_rd
        call    fcb_clear_tail
        call    rd_open
        ld      de,msg_tmp
        jp      c,fatal
        ld      (ix+R_BINARY),1
text_line:
        ld      ix,tmp_rd
        call    rd_getc
        jr      c,text_pass_end
        ld      hl,pass_file
        cp      (hl)
        jr      nz,text_skip_line
        call    text_index_entry
text_copy:
        ld      ix,tmp_rd
        call    rd_getc
        jr      c,text_pass_end
        ld      (text_byte),a
        call    out_byte
        call    text_advance
        ld      a,(text_byte)
        cp      0Dh
        jr      nz,text_copy
        ld      hl,(text_lines)
        inc     hl
        ld      (text_lines),hl
        jr      text_line
text_skip_line:
        ld      ix,tmp_rd
        call    rd_getc
        jr      c,text_pass_end
        cp      0Dh
        jr      nz,text_skip_line
        jr      text_line
text_pass_end:
        ld      a,(pass_file)
        inc     a
        ld      (pass_file),a
        ld      hl,file_count
        cp      (hl)
        jr      c,text_pass
        ret

; The line that is going to be written is the (text_lines+1)th: when it is the first of
; 16, its place goes to the index.
text_index_entry:
        ld      hl,(text_lines)
        ld      a,l
        and     15
        ret     nz
        ld      b,4
index_shift:
        srl     h
        rr      l
        djnz    index_shift
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,de
        ld      de,(off_text)
        add     hl,de
        ld      de,hdrbuf+128
        add     hl,de
        ld      de,(text_record)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      a,(text_offset)
        ld      (hl),a
        ret

; One more byte of the text: the place in it goes on.
text_advance:
        ld      a,(text_offset)
        inc     a
        cp      128
        jr      c,advance_keep
        xor     a
        ld      hl,(text_record)
        inc     hl
        ld      (text_record),hl
advance_keep:
        ld      (text_offset),a
        ret

; The header and the index go to the first records of the file that is closed now: it is
; opened again and they are written by record number.
write_head:
        ld      ix,dbg_wr
        call    fcb_clear_tail
        ld      de,dbg_wr
        ld      c,15
        call    BDOS
        inc     a
        ld      de,msg_reopen
        jp      z,fatal
        ld      hl,0
        ld      (head_record),hl
        ld      hl,hdrbuf
        ld      (head_pointer),hl
head_next:
        ld      de,(head_pointer)
        ld      c,26
        call    BDOS
        ld      hl,(head_record)
        ld      (dbg_wr+33),hl
        xor     a
        ld      (dbg_wr+35),a
        ld      de,dbg_wr
        ld      c,34
        call    BDOS
        or      a
        ld      de,msg_full
        jp      nz,fatal
        ld      hl,(head_pointer)
        ld      de,128
        add     hl,de
        ld      (head_pointer),hl
        ld      hl,(head_record)
        inc     hl
        ld      (head_record),hl
        ld      a,(blob_records)
        inc     a
        cp      l
        jr      nz,head_next
        ld      de,dbg_wr
        ld      c,16
        call    BDOS
        inc     a
        ld      de,msg_full
        jp      z,fatal
        ret

; The name of the file and what is in it.
report: ld      hl,dbg_wr+1
        call    put_file_name
        ld      hl,text_records_is
        call    put_text
        ld      hl,(rec_text)
        ld      de,(text_record)
        add     hl,de
        ld      a,(text_offset)
        or      a
        jr      z,report_records
        inc     hl
report_records:
        call    put_number
        ld      hl,text_records
        call    put_text
        ld      hl,(total_lines)
        call    put_number
        ld      hl,text_lines_files
        call    put_text
        ld      a,(file_count)
        ld      l,a
        ld      h,0
        call    put_number
        ld      hl,text_files_labels
        call    put_text
        ld      hl,(label_count)
        call    put_number
        ld      hl,text_labels
        call    put_text
        ld      hl,(duplicates)
        ld      a,h
        or      l
        jr      z,report_end
        call    put_number
        ld      hl,text_duplicates
        call    put_text
report_end:
        jp      print_crlf

        include "cpm_fcb.asm"
        include "cpm_args.asm"
        include "cpm_io.asm"
        include "decimal.asm"

ext_prn:        defm    "PRN"
ext_com:        defm    "COM"
ext_dbg:        defm    "DBG"
ext_tmp:        defm    "$$$"
tmp_name:       defm    "MKDBG   "
text_mac:       defm    ".MAC"
text_records_is: defm   ": ",0
text_records:   defm    " records, ",0
text_lines_files: defm  " lines, ",0
text_files_labels: defm " files, ",0
text_labels:    defm    " labels",0
text_duplicates: defm   " labels repeated: not kept",0
msg_usage:      defm    "Usage: MKDBG [-b ADDR] [-d ADDR] [d:]PROG  (PROG.PRN and PROG.COM make PROG.DBG)",13,10,'$'
msg_no_com:     defm    "The program (.COM) is not there",13,10,'$'
msg_no_prn:     defm    "The listing (.PRN) is not there",13,10,'$'
msg_directory:  defm    "The directory is full",13,10,'$'
msg_full:       defm    "The disk is full",13,10,'$'
msg_tmp:        defm    "The temporary file cannot be read",13,10,'$'
msg_reopen:     defm    "The debug file cannot be opened again",13,10,'$'
msg_entries:    defm    "Too many lines of code (3000 addresses)",13,10,'$'
msg_line_table: defm    "Too many lines of code (3000 lines)",13,10,'$'
msg_labels:     defm    "Too many labels (300)",13,10,'$'
msg_files:      defm    "Too many included files (15)",13,10,'$'
msg_segments:   defm    "Too many changes of file (64)",13,10,'$'
msg_mixed:      defm    "A program with ASEG and CSEG code is not supported",13,10,'$'
msg_lines:      defm    "More than 60000 lines of source",13,10,'$'
msg_incomplete: defm    "The listing is not complete (no page of symbols)",13,10,'$'
msg_wrap:       defm    "The code does not fit below FFFFh at that address",13,10,'$'
msg_index:      defm    "The index is more than 16 records: NSADB cannot read it",13,10,'$'
args:           defw    0

image_end:
vars:
opt_base:       equ     vars
opt_dbase:      equ     opt_base+2
opt_has_dbase:  equ     opt_dbase+2
opt_has_base:   equ     opt_has_dbase+1
seen_absolute:  equ     opt_has_base+1
seen_relocatable: equ   seen_absolute+1
have_end:       equ     seen_relocatable+1
have_name:      equ     have_end+1
dbg_started:    equ     have_name+1
listing_done:   equ     dbg_started+1
skip_lines:     equ     listing_done+1
include_state:  equ     skip_lines+1
include_file:   equ     include_state+1
line_file:      equ     include_file+1
file_count:     equ     line_file+1
segment_count:  equ     file_count+1
previous_zero:  equ     segment_count+1
pass_file:      equ     previous_zero+1
text_offset:    equ     pass_file+1
text_byte:      equ     text_offset+1
row_marker:     equ     text_byte+1
row_has_addr:   equ     row_marker+1
row_is_code:    equ     row_has_addr+1
text_length:    equ     row_is_code+1
blob_records:   equ     text_length+1
row_addr:       equ     blob_records+1
row_length:     equ     row_addr+2
row_end:        equ     row_length+2
last_sequence:  equ     row_end+2
lines_before:   equ     last_sequence+2
base_final:     equ     lines_before+2
duplicates:     equ     base_final+2
entry_count:    equ     duplicates+2
line_count:     equ     entry_count+2
label_count:    equ     line_count+2
total_lines:    equ     label_count+2
prog_records:   equ     total_lines+2
text_lines:     equ     prog_records+2
text_record:    equ     text_lines+2
text_count:     equ     text_record+2
text_pointer:   equ     text_count+2
statement_text: equ     text_pointer+2
search_low:     equ     statement_text+2
search_high:    equ     search_low+2
search_mid:     equ     search_high+2
search_value:   equ     search_mid+2
search_count:   equ     search_value+2
put_address:    equ     search_count+2
put_key:        equ     put_address+2
insert_first:   equ     put_key+2
insert_second:  equ     insert_first+2
insert_place:   equ     insert_second+2
insert_count:   equ     insert_place+2
insert_count_pointer: equ insert_count+2
work_count:     equ     insert_count_pointer+2
kept_count:     equ     work_count+2
read_pointer:   equ     kept_count+2
line_address:   equ     read_pointer+2
line_key:       equ     line_address+2
key_sequence:   equ     line_key+2
data_base:      equ     key_sequence+2
sort_i:         equ     data_base+2
sort_j:         equ     sort_i+2
sort_address:   equ     sort_j+2
addr_records:   equ     sort_address+2
line_records:   equ     addr_records+2
symbol_records: equ     line_records+2
text_entries:   equ     symbol_records+2
off_addr:       equ     text_entries+2
off_line:       equ     off_addr+2
off_symaddr:    equ     off_line+2
off_text:       equ     off_symaddr+2
rec_addr:       equ     off_text+2
rec_line:       equ     rec_addr+2
rec_symname:    equ     rec_line+2
rec_symaddr:    equ     rec_symname+2
rec_text:       equ     rec_symaddr+2
block_pointer:  equ     rec_text+2
block_count:    equ     block_pointer+2
head_record:    equ     block_count+2
head_pointer:   equ     head_record+2
found_pointer:  equ     head_pointer+2
com_head:       equ     found_pointer+2
include_name:   equ     com_head+3
end_name:       equ     include_name+12
files:          equ     end_name+NAME_MAX
segments:       equ     files+MAX_FILES*FILE_SIZE
vars_end:       equ     segments+MAX_SEGMENTS*SEG_SIZE
orig_sp:        equ     vars_end
args_pos:       equ     orig_sp+2
numbuf:         equ     args_pos+2
name_fcb:       equ     numbuf+8
com_fcb:        equ     name_fcb+16
work:           equ     com_fcb+36
word:           equ     work+130
dir_buffer:     equ     word+64
name_buffer:    equ     dir_buffer+128
word_buffer:    equ     name_buffer+32
linebuf:        equ     word_buffer+16
textbuf:        equ     linebuf+LINE_MAX+2
prn_rd:         equ     textbuf+TEXT_MAX+2
tmp_rd:         equ     prn_rd+R_SIZE
tmp_wr:         equ     tmp_rd+R_SIZE
dbg_wr:         equ     tmp_wr+W_SIZE
hdrbuf:         equ     dbg_wr+W_SIZE
label_order:    equ     hdrbuf+(BLOB_MAX+1)*128
labels:         equ     label_order+MAX_LABELS*2
entries:        equ     labels+MAX_LABELS*LABEL_SIZE
lines_tab:      equ     entries+MAX_ENTRIES*4
stack_low:      equ     lines_tab+MAX_LINES*4
stack_top:      equ     stack_low+256
