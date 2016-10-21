; DIFF: show the lines that two text files do not have in common.
;
;     DIFF [d:]file1 [d:]file2
;
; A line only in the first file is shown as `< number: line`, one only in the second as
; `> number: line`. The files are compared line by line; when they differ, the next lines
; of each are looked at (up to 6 ahead) to find where they agree again, so an inserted or
; a deleted line does not make all the lines after it different. A part that is changed
; much more than that is shown as all its lines of the first file and then all those of the
; second. A line `---` is between the `<` lines and the `>` lines of a change. The
; lines are cut at 99 characters for the comparison.

BDOS:           equ     0005h
TAIL:           equ     0080h
LINE_LENGTH:    equ     100
AHEAD:          equ     6
WINDOW:         equ     AHEAD+1

        org     0100h
start:  ld      (orig_sp),sp
        ld      sp,stack_top
        ld      hl,names
        ld      de,names+1
        ld      bc,flags_end-names-1
        ld      (hl),0
        ldir
        call    main
        ld      sp,(orig_sp)
        ret

main:   call    args_init
main_word:
        call    next_word
        jr      c,main_run
        ld      a,(word)
        cp      '-'
        jr      z,usage
        ld      a,(names)
        cp      2
        jr      nc,usage
        ld      de,reader_a
        or      a
        jr      z,main_parse
        ld      de,reader_b
main_parse:
        ld      hl,word
        call    parse_fcb
        ld      hl,names
        inc     (hl)
        jr      main_word
main_run:
        ld      a,(names)
        cp      2
        jp      z,diff_start
usage:  ld      de,msg_usage
        jp      print

tool_option:
        scf
        ret

diff_start:
        ld      ix,reader_a
        call    fcb_clear_tail
        ld      ix,reader_b
        call    fcb_clear_tail
        ld      ix,reader_a
        call    rd_open
        jp      c,open_failed
        ld      ix,reader_b
        call    rd_open
        jp      c,open_failed
        ld      hl,1
        ld      (base_a),hl
        ld      (base_b),hl
diff_loop:
        call    fill_a
        call    fill_b
        ld      a,(count_a)
        ld      hl,count_b
        or      (hl)
        jp      z,diff_done
        ld      a,(count_a)
        or      a
        jp      z,diff_lone
        ld      a,(count_b)
        or      a
        jp      z,diff_lone
        ld      hl,win_a
        ld      de,win_b
        call    text_equal
        jr      nz,diff_differ
        xor     a
        ld      (last_side),a
        ld      b,1
        ld      c,1
        call    advance
        jr      diff_loop
; The heads are different: look for the nearest place where the two files agree again.
diff_differ:
        ld      a,1
        ld      (distance),a
diff_distance:
        ld      a,(distance)
        ld      b,a
        xor     a
        ld      (ahead_a),a
diff_pair:
        ld      a,(ahead_a)
        ld      c,a
        ld      a,(distance)
        sub     c
        jr      c,diff_next_distance
        ld      (ahead_b),a
        cp      WINDOW
        jr      nc,diff_next_pair
        ld      a,(ahead_a)
        ld      hl,count_a
        cp      (hl)
        jr      nc,diff_next_pair
        ld      a,(ahead_b)
        ld      hl,count_b
        cp      (hl)
        jr      nc,diff_next_pair
        ld      a,(ahead_a)
        ld      hl,win_a
        call    line_pointer
        push    hl
        ld      a,(ahead_b)
        ld      hl,win_b
        call    line_pointer
        ex      de,hl
        pop     hl
        call    text_equal
        jr      z,diff_found
diff_next_pair:
        ld      hl,ahead_a
        inc     (hl)
        ld      a,(hl)
        cp      WINDOW
        jr      c,diff_pair
diff_next_distance:
        ld      hl,distance
        inc     (hl)
        ld      a,(hl)
        cp      2*AHEAD+1
        jr      c,diff_distance
        ; no place within reach: the head of each file is different
        ld      a,(count_a)
        or      a
        jr      z,diff_lone_b
        ld      hl,win_a
        ld      a,'<'
        ld      de,(base_a)
        call    show_line
        ld      b,1
        ld      c,0
        call    advance
        jp      diff_loop
diff_lone_b:
        ld      a,(count_b)
        or      a
        jp      z,diff_loop
        ld      hl,win_b
        ld      a,'>'
        ld      de,(base_b)
        call    show_line
        ld      b,0
        ld      c,1
        call    advance
        jp      diff_loop
; The two files have the same line at the distance (ahead_a, ahead_b): what comes before
; it in each file is different.
diff_found:
        xor     a
        ld      (shown),a
found_a:
        ld      a,(shown)
        ld      hl,ahead_a
        cp      (hl)
        jr      nc,found_b_start
        ld      hl,win_a
        call    line_pointer
        push    hl
        ld      a,(shown)
        ld      c,a
        ld      b,0
        ld      hl,(base_a)
        add     hl,bc
        ex      de,hl
        pop     hl
        ld      a,'<'
        call    show_line
        ld      hl,shown
        inc     (hl)
        jr      found_a
found_b_start:
        xor     a
        ld      (shown),a
found_b:
        ld      a,(shown)
        ld      hl,ahead_b
        cp      (hl)
        jr      nc,found_skip
        ld      hl,win_b
        call    line_pointer
        push    hl
        ld      a,(shown)
        ld      c,a
        ld      b,0
        ld      hl,(base_b)
        add     hl,bc
        ex      de,hl
        pop     hl
        ld      a,'>'
        call    show_line
        ld      hl,shown
        inc     (hl)
        jr      found_b
found_skip:
        ld      a,(ahead_a)
        inc     a
        ld      b,a
        ld      a,(ahead_b)
        inc     a
        ld      c,a
        call    advance
        jp      diff_loop
; One file has no more lines: the rest of the other is different.
diff_lone:
        ld      a,(count_a)
        or      a
        jr      z,diff_lone_only_b
        ld      hl,win_a
        ld      a,'<'
        ld      de,(base_a)
        call    show_line
        ld      b,1
        ld      c,0
        call    advance
        jp      diff_loop
diff_lone_only_b:
        jp      diff_lone_b
diff_done:
        ld      a,(different)
        or      a
        ret     nz
        ld      de,msg_same
        jp      print

open_failed:
        ld      de,msg_no_file
        jp      print

; The prefix A, the line number DE and the line at HL, on the console.
show_line:
        ld      (show_prefix),a
        ld      (show_text),hl
        ld      (show_number),de
        ld      a,1
        ld      (different),a
        ld      a,(show_prefix)
        cp      '>'
        jr      nz,show_side
        ld      a,(last_side)
        cp      '<'
        jr      nz,show_side
        ld      de,msg_separator
        call    print
show_side:
        ld      a,(show_prefix)
        ld      (last_side),a
        ld      a,(show_prefix)
        ld      e,a
        call    put_char
        ld      e,' '
        call    put_char
        ld      hl,(show_number)
        call    put_number
        ld      e,':'
        call    put_char
        ld      e,' '
        call    put_char
        ld      hl,(show_text)
        call    put_text
        jp      print_crlf

; HL = the line A of the window at HL (lines of LINE_LENGTH bytes).
line_pointer:
        or      a
        ret     z
        ld      b,a
        ld      de,LINE_LENGTH
line_pointer_next:
        add     hl,de
        djnz    line_pointer_next
        ret

; The windows have up to WINDOW lines of each file: read more.
fill_a:
        ld      ix,reader_a
        ld      hl,count_a
        ld      de,eof_a
        ld      bc,win_a
        jr      fill
fill_b:
        ld      ix,reader_b
        ld      hl,count_b
        ld      de,eof_b
        ld      bc,win_b
fill:
        ld      (fill_count),hl
        ld      (fill_eof),de
        ld      (fill_window),bc
fill_next:
        ld      hl,(fill_eof)
        ld      a,(hl)
        or      a
        ret     nz
        ld      hl,(fill_count)
        ld      a,(hl)
        cp      WINDOW
        ret     nc
        ld      hl,(fill_window)
        call    line_pointer
        ex      de,hl
        ld      b,LINE_LENGTH
        call    rd_line
        jr      c,fill_end
        ld      hl,(fill_count)
        inc     (hl)
        jr      fill_next
fill_end:
        ld      hl,(fill_eof)
        ld      (hl),1
        ret

; Drop B lines from the window of the first file and C from the second.
advance:
        ld      a,c
        ld      (drop_b),a
        ld      a,b
        or      a
        jr      z,advance_second
        ld      hl,count_a
        ld      de,win_a
        call    drop_lines
        ld      a,(drop_done)
        ld      c,a
        ld      b,0
        ld      hl,(base_a)
        add     hl,bc
        ld      (base_a),hl
advance_second:
        ld      a,(drop_b)
        or      a
        ret     z
        ld      hl,count_b
        ld      de,win_b
        call    drop_lines
        ld      a,(drop_done)
        ld      c,a
        ld      b,0
        ld      hl,(base_b)
        add     hl,bc
        ld      (base_b),hl
        ret

; Drop A lines from the window at DE that has (HL) lines, or all if it has fewer; the
; number that was dropped goes to drop_done.
drop_lines:
        ld      c,a
        ld      a,(hl)
        sub     c
        jr      nc,drop_have
        ld      c,(hl)
        xor     a
drop_have:
        ld      (hl),a
        ld      (drop_left),a
        ld      a,c
        ld      (drop_done),a
        ld      (drop_window),de
        ld      a,(drop_left)
        or      a
        ret     z
        ld      a,(drop_done)
        call    times_line
        ld      de,(drop_window)
        add     hl,de
        push    hl
        ld      a,(drop_left)
        call    times_line
        ld      b,h
        ld      c,l
        pop     hl
        ld      de,(drop_window)
        ldir
        ret

; HL = A lines of LINE_LENGTH bytes.
times_line:
        ld      hl,0
        or      a
        ret     z
        ld      b,a
        ld      de,LINE_LENGTH
times_line_next:
        add     hl,de
        djnz    times_line_next
        ret

        include "cpm_fcb.asm"
        include "cpm_args.asm"
        include "cpm_io.asm"
        include "decimal.asm"

msg_usage:      defm "Usage: DIFF [d:]file1 [d:]file2",13,10,'$'
msg_no_file:    defm "DIFF: a file is not there",13,10,'$'
msg_same:       defm "No differences",13,10,'$'
msg_separator:  defm "---",13,10,'$'
args:           defw 0

image_end:
names:          equ     image_end
different:      equ     names+1
count_a:        equ     different+1
count_b:        equ     count_a+1
eof_a:          equ     count_b+1
eof_b:          equ     eof_a+1
distance:       equ     eof_b+1
ahead_a:        equ     distance+1
ahead_b:        equ     ahead_a+1
shown:          equ     ahead_b+1
drop_b:         equ     shown+1
drop_left:      equ     drop_b+1
drop_done:      equ     drop_left+1
last_side:      equ     drop_done+1
flags_end:      equ     last_side+1
orig_sp:        equ     flags_end
args_pos:       equ     orig_sp+2
base_a:         equ     args_pos+2
base_b:         equ     base_a+2
fill_count:     equ     base_b+2
fill_eof:       equ     fill_count+2
fill_window:    equ     fill_eof+2
drop_window:    equ     fill_window+2
show_prefix:    equ     drop_window+2
show_text:      equ     show_prefix+1
show_number:    equ     show_text+2
numbuf:         equ     show_number+2
work:           equ     numbuf+8
word:           equ     work+130
dir_buffer:     equ     word+64
win_a:          equ     dir_buffer+128
win_b:          equ     win_a+WINDOW*LINE_LENGTH
reader_a:       equ     win_b+WINDOW*LINE_LENGTH
reader_b:       equ     reader_a+R_SIZE
stack_low:      equ     reader_b+R_SIZE
stack_top:      equ     stack_low+128
