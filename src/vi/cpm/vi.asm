; Standard ANSI/VT100 CP/M build.
        org     0100h
start:  jp      vi_start
        include "vi_cpm_platform.asm"
        include "vi_core.asm"
        include "vi_cpm_stack.asm"
vi_end:
        include "vi_bss.asm"
        include "vi_cpm_bss.asm"
