; Window over a document that is larger than the text buffer.
;
; The text buffer holds a window of the file. The text before the window (the
; head) is in a temporary file, in pieces that start at a line start. The text
; after the window (the tail) is in a second temporary file, in pieces too,
; and below them in the source file, which is read in order. Both temporary
; files are stacks: the piece nearest the window is the last one written.
; window_balance, called once per key, keeps some text on each side of the
; cursor by moving pieces between the window and the files. A change of the
; window offsets clears the undo log.

WIN_PIECE:      equ     TEXT_SIZE/4
WIN_SLACK:      equ     TEXT_SIZE/16    ; Free room kept for typing
HEAD_MAX:       equ     64              ; Pieces in the head file
TAIL_MAX:       equ     32              ; Pieces in the tail file
BACK_MIN:       equ     WIN_PIECE/2     ; Fetch a head piece below this
FWD_MIN:        equ     WIN_PIECE/2     ; Fetch a tail piece below this

; ---------- the source file ----------

; Copy up to BC text bytes of the source file to HL, without the CRs, and stop
; at the end of the file or the CP/M end mark (src_open is then 0). Returns
; the number of bytes copied in BC.
src_fill:
        ld      (src_start),hl
        add     hl,bc
        ld      (src_end),hl
        ld      hl,(src_start)
        ex      de,hl
src_fill_next:
        ld      hl,(src_end)
        or      a
        sbc     hl,de
        jr      z,src_fill_done
        ld      a,(src_left)
        or      a
        jr      nz,src_fill_byte
        push    de
        call    src_read_record
        pop     de
        jr      c,src_fill_done
        jr      src_fill_next
src_fill_byte:
        ld      hl,(src_ptr)
        ld      a,(hl)
        inc     hl
        ld      (src_ptr),hl
        ld      hl,src_left
        dec     (hl)
        cp      01Ah
        jr      z,src_fill_end_mark
        cp      0Dh
        jr      z,src_fill_next
        ld      (de),a
        inc     de
        jr      src_fill_next
src_fill_end_mark:
        xor     a
        ld      (src_open),a
        ld      (src_left),a
src_fill_done:
        ld      hl,(src_start)
        ex      de,hl
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l
        ret

; Read the next record of the source file into src_buf. Carry is set at the
; end of the file.
src_read_record:
        ld      de,src_buf
        ld      c,26
        call    BDOS
        ld      de,src_fcb
        ld      c,20
        call    BDOS
        or      a
        jr      nz,src_read_end
        ld      hl,src_buf
        ld      (src_ptr),hl
        ld      a,128
        ld      (src_left),a
        ld      hl,(src_next_rec)
        inc     hl
        ld      (src_next_rec),hl
        or      a
        ret
src_read_end:
        xor     a
        ld      (src_open),a
        ld      (src_left),a
        scf
        ret

; Note where the unread text starts: record tell_rec and tell_skip bytes into
; it. tell_open is 0 when there is no unread text.
src_tell:
        ld      a,(src_open)
        ld      (tell_open),a
        or      a
        ret     z
        ld      hl,(src_next_rec)
        ld      a,(src_left)
        or      a
        jr      z,src_tell_aligned
        dec     hl
        ld      c,a
        ld      a,128
        sub     c
        jr      src_tell_store
src_tell_aligned:
        xor     a
src_tell_store:
        ld      (tell_skip),a
        ld      (tell_rec),hl
        ret

; Continue reading at the position src_tell noted.
src_restore:
        ld      a,(tell_open)
        or      a
        ret     z
        ld      hl,(tell_rec)
        ld      a,(tell_skip)

; Continue reading at record HL, A bytes into it. A random read loads the
; record and the extent; the sequential reads go on from the next record.
; Carry is set, and the source closed, when the record is past the end.
src_seek:
        push    af
        ld      (src_fcb+33),hl
        xor     a
        ld      (src_fcb+35),a
        ld      (src_next_rec),hl
        ld      de,src_buf
        ld      c,26
        call    BDOS
        ld      de,src_fcb
        ld      c,33
        call    BDOS
        or      a
        jr      nz,src_seek_end
        ld      hl,src_fcb+32
        inc     (hl)
        ld      hl,(src_next_rec)
        inc     hl
        ld      (src_next_rec),hl
        pop     af
        ld      c,a
        ld      b,0
        ld      hl,src_buf
        add     hl,bc
        ld      (src_ptr),hl
        ld      a,128
        sub     c
        ld      (src_left),a
        ld      a,1
        ld      (src_open),a
        or      a
        ret
src_seek_end:
        pop     af
        xor     a
        ld      (src_open),a
        ld      (src_left),a
        scf
        ret

; ---------- moving the window ----------

; Called once per key. Keep text on both sides of the cursor while the head
; or the tail has more. The limits leave room between a move and its undoing,
; so a key never fetches back what the last key moved out.
window_balance:
        ld      a,(window_failed)
        or      a
        ret     nz
        ld      a,(head_count)
        or      a
        jr      z,balance_ahead
        ld      hl,(cursor)
        ld      de,BACK_MIN
        or      a
        sbc     hl,de
        jr      nc,balance_ahead
        call    window_back
        jr      c,window_fail
balance_ahead:
        ld      a,(tail_count)
        ld      hl,src_open
        or      (hl)
        ret     z
        ld      hl,(text_len)
        ld      de,(cursor)
        or      a
        sbc     hl,de
        ld      de,FWD_MIN
        or      a
        sbc     hl,de
        ret     nc
window_more:
        ld      hl,(text_len)
        ld      de,TEXT_SIZE-WIN_PIECE-WIN_SLACK
        or      a
        sbc     hl,de
        jr      c,window_read
        jr      z,window_read
        ld      hl,(cursor)
        ld      de,WIN_PIECE+BACK_MIN
        or      a
        sbc     hl,de
        jr      c,window_read
        call    head_push
        jr      nc,window_more
window_fail:
        ld      a,1
        ld      (window_failed),a
        ld      a,7
        jp      putc
window_read:
        ld      a,(tail_count)
        or      a
        jr      nz,tail_pop
        ld      hl,TEXT_SIZE-WIN_SLACK
        ld      de,(text_len)
        or      a
        sbc     hl,de
        ret     z
        ret     c
        ld      de,WIN_PIECE
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      c,window_read_room
        ld      hl,WIN_PIECE
window_read_room:
        ld      b,h
        ld      c,l
        ld      hl,(text_len)
        ld      de,text
        add     hl,de
        call    src_fill
        ld      hl,(text_len)
        add     hl,bc
        ld      (text_len),hl
        jp      mark_all_dirty

; Move the last piece of the tail file to the end of the window, if it fits.
tail_pop:
        dec     a
        ld      de,tail_tab
        call    entry_addr
        call    entry_load
        ld      (back_rec),de
        ld      (back_len),bc
        ld      hl,(text_len)
        add     hl,bc
        ld      de,TEXT_SIZE-WIN_SLACK+1
        or      a
        sbc     hl,de
        ret     nc
        ld      hl,tail_f
        ld      (tmpf),hl
        ld      hl,(back_rec)
        ld      (tmp_rec),hl
        ld      hl,(text_len)
        ld      de,text
        add     hl,de
        ex      de,hl
        ld      bc,(back_len)
        call    tmp_read
        jp      c,window_fail
        call    mark_all_dirty
        ld      hl,(text_len)
        ld      de,(back_len)
        add     hl,de
        ld      (text_len),hl
        ld      hl,tail_count
        dec     (hl)
        ld      de,(back_rec)
        jp      tmp_release

; Move the last piece of the head file back to the front of the window. Pieces
; go from the end of the window to the tail file until it fits.
window_back:
        ld      a,(head_count)
        dec     a
        ld      de,head_tab
        call    entry_addr
        call    entry_load
        ld      (back_rec),de
        ld      (back_len),bc
window_back_room:
        ld      hl,(text_len)
        ld      de,(back_len)
        add     hl,de
        ld      de,TEXT_SIZE-WIN_SLACK+1
        or      a
        sbc     hl,de
        jr      c,window_back_fits
        call    tail_push
        ret     c
        jr      window_back_room
window_back_fits:
        ld      hl,0
        ld      bc,(back_len)
        call    open_gap
        ld      hl,head_f
        ld      (tmpf),hl
        ld      hl,(back_rec)
        ld      (tmp_rec),hl
        ld      de,text
        ld      bc,(back_len)
        call    tmp_read
        ret     c
        ld      hl,text
        ld      bc,(back_len)
        call    count_newlines
        ld      hl,(head_lines)
        or      a
        sbc     hl,de
        ld      (head_lines),hl
        ld      hl,head_count
        dec     (hl)
        ld      de,(back_rec)
        call    tmp_release
        ld      de,(back_len)
        ld      hl,(cursor)
        add     hl,de
        ld      (cursor),hl
        ld      hl,(view_offset)
        add     hl,de
        ld      (view_offset),hl
        jp      undo_clear

; Move the end of the window to the tail file: the last WIN_PIECE bytes, from
; the start of the first line in them. It is refused, with carry set, when
; that would leave too little text after the cursor.
tail_push:
        ld      a,(tail_count)
        cp      TAIL_MAX
        ccf
        ret     c
        ld      hl,(text_len)
        ld      de,(cursor)
        or      a
        sbc     hl,de
        ld      de,WIN_PIECE+FWD_MIN
        or      a
        sbc     hl,de
        ret     c
        ld      a,(tail_made)
        or      a
        jr      nz,tail_push_ready
        ld      hl,tail_f
        ld      de,tail_name
        call    file_create
        ret     c
        ld      a,1
        ld      (tail_made),a
tail_push_ready:
        ld      hl,(text_len)
        ld      de,text-WIN_PIECE
        add     hl,de
        ld      bc,WIN_PIECE
        ld      a,0Ah
        cpir
        jr      nz,tail_piece_whole
        ld      a,b
        or      c
        jr      nz,tail_piece_found
tail_piece_whole:
        ld      bc,WIN_PIECE
tail_piece_found:
        ld      (shed_len),bc
        ld      hl,(text_len)
        or      a
        sbc     hl,bc
        ld      de,text
        add     hl,de
        ld      de,tail_f
        ld      (tmpf),de
        call    tmp_write
        ret     c
        ld      a,(tail_count)
        ld      de,tail_tab
        call    entry_addr
        ld      de,(tmp_rec)
        ld      bc,(shed_len)
        call    entry_store
        ld      hl,tail_count
        inc     (hl)
        ld      hl,(text_len)
        ld      de,(shed_len)
        or      a
        sbc     hl,de
        ld      (text_len),hl
        call    undo_clear
        or      a
        ret

; HL = the entry A of the table DE (4 bytes each: record and length).
entry_addr:
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,de
        ret

; DE = the record and BC = the length stored in the entry HL.
entry_load:
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        ret

; Store the record DE and the length BC in the entry HL.
entry_store:
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      (hl),c
        inc     hl
        ld      (hl),b
        ret

; Create the temporary file HL with the name DE on the drive of the text file.
file_create:
        ld      (tmpf),hl
        ex      de,hl
        ld      a,(FCB)
        jp      tmp_create

; Move the first piece of the window to the head file: the bytes up to the
; last line end within the first WIN_PIECE bytes. The cursor must be past
; the piece. Carry is set when the file or its table is full.
head_push:
        ld      a,(head_count)
        cp      HEAD_MAX
        ccf
        ret     c
        ld      a,(head_made)
        or      a
        jr      nz,head_push_ready
        ld      hl,head_f
        ld      de,head_name
        call    file_create
        ret     c
        ld      a,1
        ld      (head_made),a
head_push_ready:
        ld      hl,text+WIN_PIECE-1
        ld      bc,WIN_PIECE
        ld      a,0Ah
        cpdr
        jr      nz,head_piece_whole
        inc     hl
        inc     hl
        ld      de,text
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l
        jr      head_piece_found
head_piece_whole:
        ld      bc,WIN_PIECE
head_piece_found:
        ld      (piece_len),bc
        ld      hl,head_f
        ld      (tmpf),hl
        ld      hl,text
        call    tmp_write
        ret     c
        ld      a,(head_count)
        ld      de,head_tab
        call    entry_addr
        ld      de,(tmp_rec)
        ld      bc,(piece_len)
        call    entry_store
        ld      hl,head_count
        inc     (hl)
        ld      hl,text
        ld      bc,(piece_len)
        call    count_newlines
        ld      hl,(head_lines)
        add     hl,de
        ld      (head_lines),hl
        ld      hl,0
        ld      bc,(piece_len)
        call    close_gap
        ld      de,(piece_len)
        ld      hl,(cursor)
        or      a
        sbc     hl,de
        ld      (cursor),hl
        ld      hl,(view_offset)
        or      a
        sbc     hl,de
        jr      nc,head_view_kept
        ld      a,1
        ld      (view_stale),a
        jr      head_view_done
head_view_kept:
        ld      (view_offset),hl
head_view_done:
        call    undo_clear
        or      a
        ret
; Delete the temporary file when the editor ends.
window_cleanup:
        ld      a,(head_made)
        or      a
        jr      z,cleanup_tail
        ld      hl,head_f
        ld      (tmpf),hl
        call    tmp_erase
cleanup_tail:
        ld      a,(tail_made)
        or      a
        ret     z
        ld      hl,tail_f
        ld      (tmpf),hl
        jp      tmp_erase

; ---------- commands that cross the window ----------

; Fetch the next piece, with the cursor at the end of the window. Carry is set
; when there is nothing more to fetch or the window has failed.
window_forward:
        ld      a,(tail_count)
        ld      hl,src_open
        or      (hl)
        jr      z,window_forward_none
        ld      a,(window_failed)
        or      a
        jr      nz,window_forward_none
        call    window_balance
        or      a
        ret
window_forward_none:
        scf
        ret

; G: the cursor goes to the end of the document.
window_end:
        ld      hl,(text_len)
        ld      (cursor),hl
        call    window_forward
        jr      nc,window_end
        ret

; Note the line of the document and the column of the cursor.
window_mark:
        ld      hl,(cursor)
        call    line_start_of
        ld      d,h
        ld      e,l
        ld      hl,(cursor)
        or      a
        sbc     hl,de
        ld      (mark_col),hl
        ld      b,d
        ld      c,e
        ld      hl,text
        call    count_newlines
        ld      hl,(head_lines)
        add     hl,de
        ld      (mark_line),hl
        ret

; Put the cursor back where window_mark noted it.
window_restore:
        ld      hl,(mark_line)
        call    goto_line
        ld      hl,(cursor)
        ld      de,(mark_col)
        add     hl,de
        ld      (cursor),hl
        ret

; Put the cursor at the start of line HL of the document (the first line is
; 0), moving the window as needed. A line after the end gives the end.
goto_line:
        ld      (goto_target),hl
goto_line_loop:
        ld      a,(window_failed)
        or      a
        ret     nz
        ld      hl,(goto_target)
        ld      de,(head_lines)
        or      a
        sbc     hl,de
        jr      nc,goto_line_inside
        ld      hl,0
        ld      (cursor),hl
        call    window_balance
        jr      goto_line_loop
goto_line_inside:
        ld      (goto_index),hl
        ld      hl,text
        ld      bc,(text_len)
        call    count_newlines
        ld      hl,(goto_index)
        or      a
        sbc     hl,de
        jr      c,goto_line_find
        jr      z,goto_line_find
        ld      hl,(text_len)
        ld      (cursor),hl
        call    window_forward
        jr      nc,goto_line_loop
goto_line_find:
        ld      hl,text
        ld      bc,(text_len)
        ld      de,(goto_index)
goto_find_loop:
        ld      a,d
        or      e
        jr      z,goto_found
        ld      a,b
        or      c
        jr      z,goto_found
        ld      a,0Ah
        cpir
        jr      nz,goto_found
        dec     de
        jr      goto_find_loop
goto_found:
        ld      de,text
        or      a
        sbc     hl,de
        ld      (cursor),hl
        ret

; The search of / and n, from (search_start). If the window has no match, go on
; in the following pieces, starting at the last line of the window; a match
; cannot span lines. When nothing is found the cursor goes back to where it was.
search_in_window:
        call    find_match
        ld      a,(match_found)
        or      a
        ret     nz
        ld      a,(tail_count)
        ld      hl,src_open
        or      (hl)
        jr      z,search_none
        ld      hl,(text_len)
        call    line_start_of
        ld      (cursor),hl
        call    window_forward
        jr      c,search_lost
        ld      hl,(cursor)
        ld      (search_start),hl
        jr      search_in_window
search_lost:
        call    window_restore
search_none:
        ld      a,1
        ld      (search_failed),a
        ret

; ---------- writing a document that is in pieces ----------

; Write head, window and unread text to VIOUT.$$$, then replace the target
; file with it. The target is kept if anything fails.
write_windowed:
        call    src_tell
        call    merge_area
        ld      hl,FCB+1
        ld      de,target_name
        ld      bc,11
        ldir
        ld      hl,out_name
        ld      de,FCB+1
        ld      bc,11
        ldir
        call    create_file
        jr      c,write_windowed_error
        call    save_begin
        call    merge_head
        jr      c,write_windowed_failed
        ld      hl,text
        ld      bc,(text_len)
        call    save_bytes
        jr      c,write_windowed_failed
        call    merge_tail
        jr      c,write_windowed_failed
        ld      hl,(out_recs)
        ld      (tail_rec),hl
        ld      a,(record_pos)
        ld      (tail_skip),a
        call    merge_src
        jr      c,write_windowed_failed
        call    save_finish
        jr      c,write_windowed_failed
        jr      publish_output
write_windowed_error:
        ld      hl,write_error_message
        call    puts
write_windowed_failed:
        ld      de,FCB
        ld      c,19
        call    BDOS
        call    restore_target_name
        call    src_restore
        scf
        ret

restore_target_name:
        ld      hl,target_name
        ld      de,FCB+1
        ld      bc,11
        ldir
        ret

; Erase the target, give it the name of the output and read the unread text
; from the new file, from the byte where it was written.
publish_output:
        ld      a,(FCB)
        ld      (ren_fcb),a
        ld      (ren_fcb+16),a
        ld      hl,out_name
        ld      de,ren_fcb+1
        ld      bc,11
        ldir
        ld      hl,target_name
        ld      de,ren_fcb+17
        ld      bc,11
        ldir
        call    restore_target_name
        ld      de,FCB
        ld      c,19
        call    BDOS
        ld      de,ren_fcb
        ld      c,23
        call    BDOS
        inc     a
        jr      z,publish_rename_failed
        xor     a
        ld      (modified),a
        ld      a,(tell_open)
        or      a
        ret     z
        ld      hl,FCB+12
        ld      b,36-12
publish_clear:
        ld      (hl),0
        inc     hl
        djnz    publish_clear
        ld      de,FCB
        ld      c,15
        call    BDOS
        inc     a
        jr      z,publish_open_failed
        ld      hl,FCB
        ld      de,src_fcb
        ld      bc,36
        ldir
        ld      hl,(tail_rec)
        ld      a,(tail_skip)
        call    src_seek
        or      a
        ret
publish_rename_failed:
        ld      hl,rename_error_message
        jr      publish_message
publish_open_failed:
        ld      hl,write_error_message
publish_message:
        call    puts
        xor     a
        ld      (src_open),a
        scf
        ret

; Copying between files record by record makes the disk seek for each record.
; Copy in batches through the free room after the window instead: merge_ptr
; is the batch buffer and merge_size its size, a multiple of 128 up to 4096
; bytes. With less than 128 bytes free it is merge_buf.
merge_area:
        ld      hl,TEXT_SIZE
        ld      de,(text_len)
        or      a
        sbc     hl,de
        ld      a,h
        cp      16
        jr      c,merge_area_fit
        ld      hl,4096
merge_area_fit:
        ld      a,l
        and     080h
        ld      l,a
        or      h
        jr      z,merge_area_small
        ld      b,h
        ld      c,l
        ld      hl,(text_len)
        ld      de,text
        add     hl,de
        jr      merge_area_set
merge_area_small:
        ld      hl,merge_buf
        ld      bc,128
merge_area_set:
        ld      (merge_ptr),hl
        ld      (merge_size),bc
        ret

; Write the pieces of the head file in order.
merge_head:
        ld      a,(head_count)
        or      a
        ret     z
        ld      hl,head_f
        ld      (tmpf),hl
        ld      hl,head_tab
        ld      bc,4
        jr      merge_table

; Write the pieces of the tail file, the last one first.
merge_tail:
        ld      a,(tail_count)
        or      a
        ret     z
        ld      hl,tail_f
        ld      (tmpf),hl
        dec     a
        ld      de,tail_tab
        call    entry_addr
        ld      bc,-4
        ld      a,(tail_count)

; Write the A pieces of the table from the entry HL on, moving BC bytes from
; one entry to the next.
merge_table:
        ld      (merge_left),a
        ld      (merge_entry),hl
        ld      (merge_step),bc
merge_table_entry:
        ld      hl,(merge_entry)
        call    entry_load
        ld      (tmp_rec),de
        ld      (piece_left),bc
        ld      de,(merge_step)
        add     hl,de
        ld      de,-3
        add     hl,de
        ld      (merge_entry),hl
merge_piece_loop:
        ld      hl,(piece_left)
        ld      a,h
        or      l
        jr      z,merge_next_entry
        ld      bc,(merge_size)
        or      a
        sbc     hl,bc
        jr      nc,merge_piece_full
        ld      bc,(piece_left)
        ld      hl,0
merge_piece_full:
        ld      (piece_left),hl
        push    bc
        ld      de,(merge_ptr)
        call    tmp_read
        pop     bc
        jr      c,merge_error
        ld      hl,(merge_ptr)
        call    save_bytes
        ret     c
        jr      merge_piece_loop
merge_next_entry:
        ld      hl,merge_left
        dec     (hl)
        jr      nz,merge_table_entry
        or      a
        ret
merge_error:
        ld      hl,write_error_message
        call    puts
        scf
        ret

; Write the rest of the source file.
merge_src:
        ld      a,(src_open)
        or      a
        ret     z
merge_src_loop:
        ld      hl,(merge_ptr)
        ld      bc,(merge_size)
        call    src_fill
        ld      a,b
        or      c
        jr      z,merge_src_check
        ld      hl,(merge_ptr)
        call    save_bytes
        ret     c
merge_src_check:
        ld      a,(src_open)
        or      a
        jr      nz,merge_src_loop
        ret

head_count:     defb 0
head_made:      defb 0
head_lines:     defw 0
window_failed:  defb 0
piece_len:      defw 0
piece_left:     defw 0
src_ptr:        defw 0
src_left:       defb 0
src_open:       defb 0
src_next_rec:   defw 0
src_start:      defw 0
src_end:        defw 0
tell_rec:       defw 0
tell_skip:      defb 0
tell_open:      defb 0
tail_rec:       defw 0
tail_skip:      defb 0
merge_entry:    defw 0
merge_left:     defb 0
merge_ptr:      defw 0
mark_line:      defw 0
mark_col:       defw 0
goto_target:    defw 0
goto_index:     defw 0
merge_step:     defw 0
back_rec:       defw 0
back_len:       defw 0
shed_len:       defw 0
tail_count:     defb 0
tail_made:      defb 0
merge_size:     defw 0
target_name:    defs 11,' '
out_recs:       defw 0
out_last:       defb 0Ah
head_name:      defm "VIHEAD  $$$"
tail_name:      defm "VITAIL  $$$"
out_name:       defm "VIOUT   $$$"
rename_error_message: defm 13,10,"Rename failed; the text is in VIOUT.$$$",'$'
