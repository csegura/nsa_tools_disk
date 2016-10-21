; Buffers that need no initial value. A wrapper includes this file after its
; vi_end label, so they follow the program image and are not in the COM file.
head_f:         equ     vi_end
head_tab:       equ     head_f+TMPF_SIZE
tail_f:         equ     head_tab+HEAD_MAX*4
tail_tab:       equ     tail_f+TMPF_SIZE
src_fcb:        equ     tail_tab+TAIL_MAX*4
src_buf:        equ     src_fcb+36
merge_buf:      equ     src_buf+128
ren_fcb:        equ     merge_buf+128
tmp_buf:        equ     ren_fcb+32
; The screen row is built only while redrawing and merge_buf is used only while
; saving, so they share the space.
row_buf:        equ     merge_buf
vi_bss_end:     equ     tmp_buf+128
