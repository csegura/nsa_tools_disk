; NorthStar Advantage Graphics CP/M build.
        org     0100h
start:  jp      vi_start
        include "vi_adv_platform.asm"
        include "vi_core.asm"
vi_end:
        include "vi_bss.asm"
