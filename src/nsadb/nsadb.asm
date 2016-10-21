; NSADB: a source-level debugger for the NorthStar Advantage under CP/M 2.2.
;
;     NSADB [d:]program [arguments]
;
; The COM file holds a loader at 0100h and, after it, the resident debugger,
; assembled for NSD_BASE. The loader copies the resident part up and jumps to it;
; the resident part then loads the program over the loader.

        include "nsadb_config.asm"

        org     0100h
start:  jp      loader
        include "nsadb_loader.asm"
img_src:

        org     NSD_BASE
        include "nsadb_resident.asm"
res_end:
        include "nsadb_bss.asm"
