; ****************************************************************************
; MegaZXNext: ZX Next core for the MEGA65
;
; Emulator test for the settings file (../zxn_cfg.asm), run by run_test.sh in
; the QNICE emulator with a FAT32 disk image attached as the SD card.
;
; Does what the Shell and PREP_START do at startup (open /zxnext/zxncfg,
; ZXN_MOUNT, ZXN_CFG_INIT), then changes the settings and calls ZXN_CFG_SAVE
; twice (the second call has nothing to save). The M2M registers are plain
; RAM, so M2M$CFM_DATA is the same word in every window: the file must hold
; the bits of T_SETTINGS, byte n = bit (n mod 16).
;
; RUN 0x8000: the core lends the card (test hook ZXN_TEST_GRANT)
; RUN 0x8002: the core never lends it: ZXN_CFG_SAVE must give up
;
; Output: the log of ZXN_MOUNT and zxn_cfg.asm, then
;   CFG: CONFIG_FILE after ZXN_CFG_INIT (0: taken from the Shell), register 9
;
; MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
; ****************************************************************************

#define ZXN_TEST
#include "../../../M2M/QNICE/dist_kit/sysdef.asm"
#include "../../../M2M/QNICE/dist_kit/monitor.def"

                .ORG    0x8000

                RBRA    _T_GRANT, 1             ; 0x8000
                RBRA    _T_NOGRANT, 1           ; 0x8002

_T_GRANT        MOVE    T_GRANT, R0
                MOVE    1, @R0
                RBRA    _T_START, 1
_T_NOGRANT      MOVE    T_GRANT, R0
                MOVE    0, @R0

_T_START        MOVE    0xFE00, SP
                MOVE    IO$CYC_STATE, R0        ; start the cycle counter
                MOVE    1, @R0
                MOVE    HANDLE_DEV, R0          ; SD card not mounted yet
                MOVE    0, @R0
                MOVE    M2M$CSR, R0             ; image in the back slot
                MOVE    M2M$CSR_SD_ACTIVE, @R0
                MOVE    INITIAL_SD, R0
                MOVE    M2M$CSR_SD_ACTIVE, @R0
                MOVE    OPTM_ICOUNT, R0         ; 31 menu lines
                MOVE    31, @R0
                MOVE    M2M$CFM_DATA, R0        ; settings at startup
                MOVE    0x0001, @R0

                ; The Shell (options.asm): mount, open the settings file,
                ; read its first byte
                MOVE    CONFIG_DEVH, R8
                MOVE    1, R9
                SYSCALL(f32_mnt_sd, 1)
                MOVE    CONFIG_DEVH, R8
                MOVE    CONFIG_FILE, R9
                MOVE    T_CFG_PATH, R10
                XOR     R11, R11
                SYSCALL(f32_fopen, 1)
                CMP     0, R10
                RBRA    _T_READ, Z
                MOVE    CONFIG_FILE, R0         ; no settings file
                MOVE    0, @R0
                RBRA    _T_MOUNT, 1
_T_READ         MOVE    CONFIG_FILE, R8
                SYSCALL(f32_fread, 1)

                ; PREP_START
_T_MOUNT        RSUB    ZXN_MOUNT, 1
                CMP     0, R8
                RBRA    _T_INIT, Z
                SYSCALL(puts, 1)
                RBRA    _T_END, 1
_T_INIT         RSUB    ZXN_CFG_INIT, 1

                ; The user changes the settings
                MOVE    M2M$CFM_DATA, R0
                MOVE    T_SETTINGS, @R0
                RSUB    ZXN_CFG_SAVE, 1
                RSUB    ZXN_CFG_SAVE, 1         ; nothing changed: no save

                MOVE    T_CFG, R8
                SYSCALL(puts, 1)
                MOVE    CONFIG_FILE, R8
                MOVE    @R8, R8
                SYSCALL(puthex, 1)
                MOVE    T_SPACE, R8
                SYSCALL(puts, 1)
                MOVE    M2M$RAMROM_DATA, R8
                ADD     9, R8
                MOVE    @R8, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)

_T_END          HALT                            ; ends the emulator run

WAIT_FOR_SD     RET
ZXN_TEST_EXT    RET                             ; zxn_mount.asm test hook

; Test hook (zxn_cfg.asm, ZXN_TEST): R4 points to register 9. The core grants
; the request (bit 1) if T_GRANT is set.
ZXN_TEST_GRANT  MOVE    T_GRANT, R8
                CMP     0, @R8
                RBRA    _T_TG_RET, Z
                MOVE    3, @R4
_T_TG_RET       RET

#include "../zxn_mount.asm"
#include "../zxn_cfg.asm"

T_SETTINGS      .EQU    0xA5C3
T_CFG_PATH      .ASCII_W "/ZXNEXT/ZXNCFG"
T_CFG           .ASCII_W "CFG: "
T_SPACE         .ASCII_W " "

; M2M registers (RAM in this test)
M2M$CSR_SD_ACTIVE .EQU  0x0100
M2M$CSR         .BLOCK  1
M2M$RAMROM_DEV  .BLOCK  1
M2M$RAMROM_4KWIN .BLOCK 1
M2M$RAMROM_DATA .BLOCK  0x18
M2M$CFM_ADDR    .BLOCK  1
M2M$CFM_DATA    .BLOCK  1

; Shell variables
HANDLE_DEV      .BLOCK  FAT32$DEV_STRUCT_SIZE
CONFIG_DEVH     .BLOCK  FAT32$DEV_STRUCT_SIZE
CONFIG_FILE     .BLOCK  FAT32$FDH_STRUCT_SIZE
INITIAL_SD      .BLOCK  1
OPTM_ICOUNT     .BLOCK  1
ZXN_FH          .BLOCK  FAT32$FDH_STRUCT_SIZE
ZXN_LBA         .BLOCK  2
ZXN_SECTORS     .BLOCK  2
ZXN_NCLUS       .BLOCK  2
ZXN_SPC         .BLOCK  1
ZXN_NEXT        .BLOCK  1
ZXN_CFG_FH      .BLOCK  FAT32$FDH_STRUCT_SIZE
ZXN_CFG_OLD     .BLOCK  16
T_GRANT         .BLOCK  1
