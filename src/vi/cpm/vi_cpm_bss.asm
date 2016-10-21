; The document, the yank buffer and the undo log follow the buffers of
; vi_bss.asm, so they are not in the COM file.
text:           equ     vi_bss_end
yank_buffer:    equ     text+TEXT_SIZE
undo_buffer:    equ     yank_buffer+CPM_YANK_SIZE
cpm_mem_end:    equ     undo_buffer+UNDO_SIZE
