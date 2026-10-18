; ****************************************************************************
; ZX Spectrum Next for MEGA65 (MegaZXNext)
;
; Emulator test for ZXN_MOUNT (../zxn_mount.asm), run by run_test.sh in the
; QNICE emulator with a FAT32 disk image attached as the SD card.
;
; The M2M registers and the Shell variables that ZXN_MOUNT uses are plain
; RAM here. test_zxn_mount_hw.asm builds the same program for a MEGA65 (load
; it with the QNICE monitor; it only reads the SD card). The program prints
; what ZXN_MOUNT would hand over to the core:
;   RESULT: 0000                                  or the error message
;   EXT: virtual, physical       (one line per extent)
;   REGS: size lo, size hi, slot, mounted, (unused), extents
;
; MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
; ****************************************************************************

#define ZXN_TEST
#include "../../../M2M/QNICE/dist_kit/sysdef.asm"
#include "../../../M2M/QNICE/dist_kit/monitor.def"

                .ORG    0x8000

                MOVE    0xFE00, SP
                MOVE    HANDLE_DEV, R0          ; SD card not mounted yet
                MOVE    0, @R0
                MOVE    M2M$CSR, R0             ; image in the back slot
                MOVE    M2M$CSR_SD_ACTIVE, @R0

                RSUB    ZXN_MOUNT, 1

                MOVE    R8, R0
                MOVE    R9, R1
                MOVE    T_RESULT, R8
                SYSCALL(puts, 1)
                CMP     0, R0
                RBRA    _T_OK, Z
                MOVE    R0, R8                  ; error message
                SYSCALL(puts, 1)
                MOVE    T_CODE, R8
                SYSCALL(puts, 1)
                MOVE    R1, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                RBRA    _T_END, 1

_T_OK           MOVE    R0, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                MOVE    T_REGS, R8
                SYSCALL(puts, 1)
                MOVE    M2M$RAMROM_DATA, R0     ; 2 .. 8: size, slot, mounted, -, count, direct
                ADD     2, R0
                MOVE    7, R1
_T_REGS         MOVE    @R0++, R8
                SYSCALL(puthex, 1)
                MOVE    T_SPACE, R8
                SYSCALL(puts, 1)
                SUB     1, R1
                RBRA    _T_REGS, !Z
                SYSCALL(crlf, 1)

#ifdef ZXN_TEST_HW
_T_END          SYSCALL(exit, 1)                ; back to the monitor (on a MEGA65)
#else
_T_END          HALT                            ; ends the emulator run
#endif

WAIT_FOR_SD     RET

; Test hook (zxn_mount.asm, ZXN_TEST): log each extent written to the core
; "EXT: virtual high, virtual low, physical high, physical low"
ZXN_TEST_EXT    INCRB
                MOVE    R8, R0
                MOVE    R9, R1
                MOVE    T_EXT, R8
                SYSCALL(puts, 1)
                MOVE    M2M$RAMROM_DATA, R2
                ADD     0x11, R2
                MOVE    @R2, R8
                SYSCALL(puthex, 1)
                SUB     1, R2
                MOVE    @R2, R8
                SYSCALL(puthex, 1)
                MOVE    T_SPACE, R8
                SYSCALL(puts, 1)
                ADD     3, R2
                MOVE    @R2, R8
                SYSCALL(puthex, 1)
                SUB     1, R2
                MOVE    @R2, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                MOVE    R0, R8
                MOVE    R1, R9
                DECRB
                RET

#include "../zxn_mount.asm"

T_RESULT        .ASCII_W "RESULT: "
T_CODE          .ASCII_W "CODE: "
T_REGS          .ASCII_W "REGS: "
T_SPACE         .ASCII_W " "
T_EXT           .ASCII_W "EXT: "

; M2M registers (RAM in this test)
M2M$CSR_SD_ACTIVE .EQU  0x0100
M2M$CSR         .BLOCK  1
M2M$RAMROM_DEV  .BLOCK  1
M2M$RAMROM_4KWIN .BLOCK 1
M2M$RAMROM_DATA .BLOCK  0x18

; Shell variables
HANDLE_DEV      .BLOCK  FAT32$DEV_STRUCT_SIZE
ZXN_FH          .BLOCK  FAT32$FDH_STRUCT_SIZE
ZXN_LBA         .BLOCK  2
ZXN_SECTORS     .BLOCK  2
ZXN_NCLUS       .BLOCK  2                       ; clusters of the image (low, high)
ZXN_SPC         .BLOCK  1                       ; sectors per cluster
ZXN_NEXT        .BLOCK  1                       ; extents written so far
