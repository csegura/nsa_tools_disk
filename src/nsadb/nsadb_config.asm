; Layout of NSADB. The resident part lives at NSD_BASE, above the program that is
; debugged, which keeps the TPA below it. The BDOS entry that the program sees at
; 0006h is NSD_BASE itself, so it takes NSD_BASE as the top of its memory. The resident part
; and its buffers (nsd_bss_end) have to end below the BDOS: it starts at D200h on the
; Advantage HQ system (rev 1.2.0), where the old base of 9000h overwrote it. It cannot be
; below 8000h (video RAM replaces 4000h-7FFFh while a glyph is written).
NSD_BASE:       equ     08800h
NSD_PROG:       equ     0100h           ; Where the program is loaded
BDOS:           equ     0005h
TAIL:           equ     0080h
FCB1:           equ     005Ch
FCB2:           equ     006Ch
