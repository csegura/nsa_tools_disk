; The serial board of the Advantage (the SIO board, a uPD8251), shared by XMODEM and TERM. The
; program defines the variables baud_code, port_data, port_control, port_baud (bytes) and
; rx_seconds (a byte).
;
; The board is the one whose identity port (70h to 75h) reads F7h (the emulator) or E8h to EFh
; (the boot ROM of the machine tests the id AND F8h for E8h): the slots 6 to 1, whose ports
; are 00h-0Fh to 50h-5Fh. The baud rate code goes to the baud port:
;   7Fh 19200   7Eh 9600   7Ch 4800   78h 2400   70h 1200   60h 600   40h 300
; (the board is reset to 150 baud, so the program always writes it).

; Find the board. Carry when no board is F7h.
sio_find:
        ld      b,0
        ld      c,70h
sio_find_next:
        in      a,(c)
        cp      0F7h
        jr      z,sio_found
        and     0F8h
        cp      0E8h
        jr      z,sio_found
        inc     c
        inc     b
        ld      a,b
        cp      6
        jr      nz,sio_find_next
        scf
        ret
sio_found:
        ld      a,b
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        ld      (port_data),a
        inc     a
        ld      (port_control),a
        add     a,7                     ; the baud register is at +8 (siobps of the boot ROM)
        ld      (port_baud),a
        or      a
        ret

; Reset the chip (three zeros and a reset command leave it waiting for the mode in any
; state), then the baud rate, the mode (8 bits, no parity, 1 stop bit, 16 times the baud rate:
; 4Eh; the boot ROM uses CEh, 2 stop bits) and the command (transmit, receive, DTR,
; RTS, clear the errors). The same order as the boot ROM.
sio_setup:
        ld      a,(port_control)
        ld      c,a
        xor     a
        out     (c),a
        out     (c),a
        out     (c),a
        ld      a,40h
        out     (c),a
        ld      a,(port_baud)
        ld      d,c
        ld      c,a
        ld      a,(baud_code)
        out     (c),a
        ld      c,d
        ld      a,(sio_mode)
        out     (c),a
        ld      a,37h
        out     (c),a
        ld      a,(port_data)
        ld      c,a
        in      a,(c)                   ; the chip may hold junk bytes after the reset: the boot
        in      a,(c)                   ; ROM reads two of them and throws them away
        ret

; The mode byte: 4Eh is 8 bits, no parity, 1 stop bit. A program that wants other values writes it
; before sio_setup.
sio_mode:       defb    4Eh

; Send the byte A.
sio_tx:
        ld      b,a
        ld      a,(port_control)
        ld      c,a
sio_tx_wait:
        in      a,(c)
        and     1
        jr      z,sio_tx_wait
        ld      a,(port_data)
        ld      c,a
        ld      a,b
        out     (c),a
        ret

; A byte from the line if there is one now: A, with carry clear; carry set when there is
; none. Destroys C.
sio_poll:
        ld      a,(port_control)
        ld      c,a
        in      a,(c)
        and     2
        jr      nz,sio_poll_have
        scf
        ret
sio_poll_have:
        ld      a,(port_data)
        ld      c,a
        in      a,(c)
        or      a
        ret

; A byte from the line within about A * 0.8 seconds. Carry on a timeout.
sio_rx_wait:
        ld      (rx_seconds),a
sio_rx_second:
        ld      hl,0
sio_rx_loop:
        ld      a,(port_control)
        ld      c,a
        in      a,(c)
        and     2
        jr      nz,sio_poll_have
        dec     hl
        ld      a,h
        or      l
        jr      nz,sio_rx_loop
        ld      a,(rx_seconds)
        dec     a
        ld      (rx_seconds),a
        jr      nz,sio_rx_second
        scf
        ret

; Throw away what comes until the line has been quiet for a second.
sio_purge:
        ld      a,1
        call    sio_rx_wait
        jr      nc,sio_purge
        ret
