; XMODEM: send or receive a file over the serial board (the SIO board of the Advantage) with
; the XMODEM protocol, which is how a file gets to or from another computer.
;
;     XMODEM -s [-c] [d:]file       send the file
;     XMODEM -r [-c] [-f] [d:]file  receive into the file (-f replaces one that is there)
;
; The line is set to 9600 baud (-b gives 19200), 8 bits, no parity, two stop bits (the setup of the boot ROM). -c uses
; the 16 bit CRC of XMODEM-CRC in place of the one byte checksum (the receiver asks for it
; and the sender follows what the receiver asks for). The file is sent and received in
; records of 128 bytes, as CP/M has it, so a file that is received is filled with Ctrl-Z
; (or whatever the sender filled the last block with) to a record.
;
; The board is the one whose identity port (70h to 75h) reads F7h. A key does not stop a
; transfer: if the other side does not answer, it ends by itself after about 10 tries.

BDOS:           equ     0005h
TAIL:           equ     0080h
SOH:            equ     01h
EOT:            equ     04h
ACK:            equ     06h
NAK:            equ     15h
CAN:            equ     18h
CRC_REQUEST:    equ     'C'
TRIES:          equ     10

        org     0100h
start:  ld      (orig_sp),sp
        ld      sp,stack_top
        ld      hl,flag_send
        ld      de,flag_send+1
        ld      bc,flags_end-flag_send-1
        ld      (hl),0
        ldir
        ld      a,7Eh
        ld      (baud_code),a
        call    main
        ld      sp,(orig_sp)
        ret

main:   call    args_init
main_word:
        call    next_word
        jr      c,main_run
        ld      a,(word)
        cp      '-'
        jr      nz,main_name
        call    parse_options
        jr      nc,main_word
        jr      usage
main_name:
        ld      a,(names)
        or      a
        jr      nz,usage
        inc     a
        ld      (names),a
        ld      hl,word
        ld      de,fcb
        call    parse_fcb
        jr      main_word
main_run:
        ld      a,(names)
        or      a
        jr      z,usage
        ld      a,(flag_send)
        ld      hl,flag_receive
        xor     (hl)
        jr      z,usage
        ld      hl,fcb
        ld      de,fcb+1
        ld      a,(de)
        cp      ' '
        jr      z,usage
        ld      b,11
main_wild:
        ld      a,(de)
        cp      '?'
        jr      z,usage
        inc     de
        djnz    main_wild
        ld      ix,fcb
        call    fcb_clear_tail
        call    sio_find
        jr      nc,main_board
        ld      de,msg_no_board
        jp      print
main_board:
        call    sio_setup
        ld      a,(flag_send)
        or      a
        jp      nz,send_file
        jp      receive_file
usage:  ld      de,msg_usage
        jp      print

tool_option:
        ld      hl,flag_send
        cp      'S'
        jr      z,option_set
        ld      hl,flag_receive
        cp      'R'
        jr      z,option_set
        ld      hl,flag_crc
        cp      'C'
        jr      z,option_set
        ld      hl,flag_force
        cp      'F'
        jr      z,option_set
        cp      'B'
        scf
        ret     nz
        ld      a,7Fh
        ld      (baud_code),a
        or      a
        ret
option_set:
        ld      (hl),1
        or      a
        ret

; ---------- the block ----------
; The checksum or the CRC of the 128 bytes at `data`, to `check` (a byte, or a word).
compute_check:
        ld      hl,block_data
        ld      b,128
        ld      a,(flag_crc)
        or      a
        jr      nz,compute_crc
        xor     a
compute_sum:
        add     a,(hl)
        inc     hl
        djnz    compute_sum
        ld      (check),a
        ret
compute_crc:
        ld      de,0
compute_crc_byte:
        ld      a,(hl)
        inc     hl
        xor     d
        ld      d,a
        push    bc
        ld      b,8
compute_crc_bit:
        sla     e
        rl      d
        jr      nc,compute_crc_next
        ld      a,d
        xor     10h
        ld      d,a
        ld      a,e
        xor     21h
        ld      e,a
compute_crc_next:
        djnz    compute_crc_bit
        pop     bc
        djnz    compute_crc_byte
        ld      (check),de
        ret

; ---------- receive ----------
receive_file:
        ld      ix,fcb
        ld      de,fcb
        ld      c,15
        call    BDOS
        inc     a
        jr      z,receive_new
        ld      a,(flag_force)
        or      a
        jr      nz,receive_replace
        ld      de,msg_exists
        jp      print
receive_replace:
        ld      de,fcb
        ld      c,19
        call    BDOS
receive_new:
        ld      de,fcb
        ld      c,22
        call    BDOS
        inc     a
        jr      nz,receive_made
        ld      de,msg_full
        jp      print
receive_made:
        ld      a,1
        ld      (file_made),a
        xor     a
        ld      (fcb+32),a
        ld      a,1
        ld      (expected),a
        ld      a,TRIES
        ld      (tries),a
        call    sio_purge
; Ask the sender to start: C or NAK, until something comes.
receive_ask:
        ld      a,(flag_crc)
        or      a
        ld      a,NAK
        jr      z,receive_ask_send
        ld      a,CRC_REQUEST
receive_ask_send:
        call    sio_tx
        ld      a,4
        call    sio_rx_wait
        jr      nc,receive_header
        ld      hl,tries
        dec     (hl)
        jr      nz,receive_ask
        jp      transfer_failed
receive_next:
        ld      a,12
        call    sio_rx_wait
        jr      c,receive_timeout
receive_header:
        cp      SOH
        jr      z,receive_block
        cp      EOT
        jr      z,receive_end
        cp      CAN
        jp      z,transfer_cancelled
        jr      receive_next
receive_timeout:
        ld      hl,tries
        dec     (hl)
        jp      z,transfer_failed
        ld      a,NAK
        call    sio_tx
        jr      receive_next
receive_end:
        ld      a,ACK
        call    sio_tx
        ld      de,fcb
        ld      c,16
        call    BDOS
        inc     a
        jr      nz,receive_done
        ld      de,msg_full
        jp      print
receive_done:
        ld      de,msg_done
        jp      print
; The block number, its complement, the data and the check.
receive_block:
        ld      a,2
        call    sio_rx_wait
        jp      c,receive_bad
        ld      (block_number),a
        ld      a,2
        call    sio_rx_wait
        jp      c,receive_bad
        ld      (block_inverse),a
        ld      hl,block_data
        ld      b,128
receive_data:
        push    hl
        push    bc
        ld      a,2
        call    sio_rx_wait
        pop     bc
        pop     hl
        jp      c,receive_bad
        ld      (hl),a
        inc     hl
        djnz    receive_data
        ld      a,2
        call    sio_rx_wait
        jp      c,receive_bad
        ld      (received),a
        ld      a,(flag_crc)
        or      a
        jr      z,receive_verify
        ld      a,2
        call    sio_rx_wait
        jp      c,receive_bad
        ld      (received+1),a
receive_verify:
        call    compute_check
        ld      a,(flag_crc)
        or      a
        jr      nz,receive_verify_crc
        ld      a,(check)
        ld      hl,received
        cp      (hl)
        jp      nz,receive_bad
        jr      receive_checked
receive_verify_crc:
        ld      a,(check+1)
        ld      hl,received
        cp      (hl)
        jp      nz,receive_bad
        ld      a,(check)
        ld      hl,received+1
        cp      (hl)
        jp      nz,receive_bad
receive_checked:
        ld      a,(block_number)
        ld      b,a
        ld      a,(block_inverse)
        xor     0FFh
        cp      b
        jp      nz,receive_bad
        ld      a,(expected)
        cp      b
        jr      z,receive_write
        dec     a
        cp      b
        jr      z,receive_ack
        ld      a,CAN
        call    sio_tx
        ld      a,CAN
        call    sio_tx
        jp      transfer_failed
receive_write:
        ld      de,block_data
        ld      c,26
        call    BDOS
        ld      de,fcb
        ld      c,21
        call    BDOS
        or      a
        jr      z,receive_written
        ld      a,CAN
        call    sio_tx
        ld      a,CAN
        call    sio_tx
        call    abandon_file
        ld      de,msg_full
        jp      print
receive_written:
        ld      hl,expected
        inc     (hl)
receive_ack:
        ld      a,TRIES
        ld      (tries),a
        ld      a,ACK
        call    sio_tx
        jp      receive_next
receive_bad:
        call    sio_purge
        ld      hl,tries
        dec     (hl)
        jp      z,transfer_failed
        ld      a,NAK
        call    sio_tx
        jp      receive_next

; ---------- send ----------
send_file:
        ld      de,fcb
        ld      c,15
        call    BDOS
        inc     a
        jr      nz,send_opened
        ld      de,msg_no_file
        jp      print
send_opened:
        xor     a
        ld      (fcb+32),a
        ld      a,1
        ld      (block_number),a
        call    sio_purge
; Wait for the receiver to ask: NAK for the checksum, C for the CRC.
        ld      a,TRIES
        ld      (tries),a
send_wait:
        ld      a,75
        call    sio_rx_wait
        jr      c,send_wait_failed
        cp      NAK
        jr      z,send_checksum
        cp      CRC_REQUEST
        jr      z,send_crc
        cp      CAN
        jp      z,transfer_cancelled
        jr      send_wait
send_wait_failed:
        jp      transfer_failed
send_checksum:
        xor     a
        ld      (flag_crc),a
        jr      send_next_block
send_crc:
        ld      a,1
        ld      (flag_crc),a
send_next_block:
        ld      de,block_data
        ld      c,26
        call    BDOS
        ld      de,fcb
        ld      c,20
        call    BDOS
        or      a
        jr      nz,send_eot
        call    compute_check
        ld      a,TRIES
        ld      (tries),a
send_again:
        ld      a,SOH
        call    sio_tx
        ld      a,(block_number)
        call    sio_tx
        ld      a,(block_number)
        xor     0FFh
        call    sio_tx
        ld      hl,block_data
        ld      b,128
send_data:
        push    hl
        push    bc
        ld      a,(hl)
        call    sio_tx
        pop     bc
        pop     hl
        inc     hl
        djnz    send_data
        ld      a,(flag_crc)
        or      a
        jr      nz,send_check_crc
        ld      a,(check)
        call    sio_tx
        jr      send_answer
send_check_crc:
        ld      a,(check+1)
        call    sio_tx
        ld      a,(check)
        call    sio_tx
send_answer:
        ld      a,12
        call    sio_rx_wait
        jr      c,send_retry
        cp      ACK
        jr      z,send_acknowledged
        cp      CAN
        jp      z,transfer_cancelled
send_retry:
        ld      hl,tries
        dec     (hl)
        jp      z,transfer_failed
        jr      send_again
send_acknowledged:
        ld      hl,block_number
        inc     (hl)
        jr      send_next_block
send_eot:
        ld      a,TRIES
        ld      (tries),a
send_eot_again:
        ld      a,EOT
        call    sio_tx
        ld      a,12
        call    sio_rx_wait
        jr      c,send_eot_retry
        cp      ACK
        jr      z,send_done
send_eot_retry:
        ld      hl,tries
        dec     (hl)
        jr      nz,send_eot_again
        jp      transfer_failed
send_done:
        ld      de,msg_done
        jp      print

transfer_cancelled:
        call    abandon_file
        ld      de,msg_cancelled
        jp      print
transfer_failed:
        call    abandon_file
        ld      de,msg_failed
        jp      print

; A file that was being received is not left half written: it is closed and erased.
abandon_file:
        ld      a,(file_made)
        or      a
        ret     z
        ld      de,fcb
        ld      c,16
        call    BDOS
        ld      de,fcb
        ld      c,19
        call    BDOS
        ld      de,msg_removed
        jp      print

        include "cpm_fcb.asm"
        include "cpm_args.asm"
        include "cpm_io.asm"
        include "adv_sio.asm"
        include "decimal.asm"

msg_usage:      defm "Usage: XMODEM -s|-r [-c] [-b] [-f] [d:]file",13,10,'$'
msg_no_board:   defm "XMODEM: there is no serial board",13,10,'$'
msg_no_file:    defm "XMODEM: the file is not there",13,10,'$'
msg_exists:     defm "XMODEM: the file is there (-f replaces it)",13,10,'$'
msg_full:       defm "XMODEM: the disk or the directory is full",13,10,'$'
msg_removed:    defm "XMODEM: the file that was being received is erased",13,10,'$'
msg_done:       defm "XMODEM: done",13,10,'$'
msg_cancelled:  defm "XMODEM: cancelled by the other side",13,10,'$'
msg_failed:     defm "XMODEM: no answer, or too many errors",13,10,'$'
args:           defw 0

image_end:
flag_send:      equ     image_end
flag_receive:   equ     flag_send+1
flag_crc:       equ     flag_receive+1
flag_force:     equ     flag_crc+1
names:          equ     flag_force+1
baud_code:      equ     names+1
port_data:      equ     baud_code+1
port_control:   equ     port_data+1
port_baud:      equ     port_control+1
expected:       equ     port_baud+1
tries:          equ     expected+1
rx_seconds:     equ     tries+1
block_number:   equ     rx_seconds+1
block_inverse:  equ     block_number+1
file_made:      equ     block_inverse+1
flags_end:      equ     file_made+1
orig_sp:        equ     flags_end
args_pos:       equ     orig_sp+2
check:          equ     args_pos+2
received:       equ     check+2
numbuf:         equ     received+2
work:           equ     numbuf+8
word:           equ     work+130
fcb:            equ     word+64
block_data:     equ     fcb+36
dir_buffer:     equ     block_data+128
stack_low:      equ     dir_buffer+128
stack_top:      equ     stack_low+128
