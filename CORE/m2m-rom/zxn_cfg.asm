; ****************************************************************************
; MegaZXNext: ZX Next core for the MEGA65 QNICE ROM: settings file
;
; Included by m2m-rom.asm and by the emulator test test/test_zxn_cfg.asm.
; Needs the M2M Shell variables CONFIG_FILE and
; INITIAL_SD, OPTM_ICOUNT, the M2M registers M2M$CFM_ADDR, M2M$CFM_DATA,
; M2M$RAMROM_DEV, M2M$RAMROM_4KWIN, M2M$RAMROM_DATA and ZXN_IMG_DEV
; (zxn_mount.asm).
;
; MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
; ****************************************************************************
;
; The options menu settings live in the file CFG_FILE (config.vhd), one byte
; per menu line, as in every M2M core. The M2M Shell loads it at startup.
; It would also save it whenever the menu is closed, but by then the core
; owns the SD card (sd_image.vhd), so the Shell must not touch the card.
;
; ZXN_CFG_INIT therefore takes the file handle away from the Shell after the
; image is mounted. ZXN_CFG_SAVE saves the settings itself after each change
; in the menu: it borrows the card from the core (register 9 of C_DEV_ZXN_IMG;
; the core finishes its sector, the ZX Next waits), writes the file and gives
; the card back. The file lies next to the image, never inside it, and it
; keeps its size, so only its own data sector is written.
;
; With a real ZX Next SD card (direct mode) the core cannot stop the ZX Next
; between two SD commands: the settings are loaded but not saved.
; ----------------------------------------------------------------------------

; Called by PREP_START after ZXN_MOUNT has mounted the image (or the card)
ZXN_CFG_INIT    INCRB

                MOVE    ZXN_CFG_FH, R0          ; no saving unless all is well
                MOVE    0, @R0
                MOVE    CONFIG_FILE, R1         ; has the Shell got the file?
                CMP     0, @R1
                RBRA    _ZXNC_I_RET, Z          ; no: nothing to save

                ; Take the file handle away from the Shell
                MOVE    FAT32$FDH_STRUCT_SIZE, R2
_ZXNC_I_CPY     MOVE    @R1++, @R0++
                SUB     1, R2
                RBRA    _ZXNC_I_CPY, !Z
                MOVE    CONFIG_FILE, R1
                MOVE    0, @R1

                MOVE    M2M$RAMROM_DEV, R0      ; select the core device
                MOVE    ZXN_IMG_DEV, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    0, @R0

                ; Not with a real ZX Next SD card
                MOVE    M2M$RAMROM_DATA, R0
                ADD     8, R0
                CMP     0, @R0                  ; 8: direct?
                RBRA    _ZXNC_I_SLOT, Z
                MOVE    ZXN_LOG_CFG_DIR, R8
                RBRA    _ZXNC_I_OFF, 1

                ; The file must be on the card that holds the image
_ZXNC_I_SLOT    MOVE    INITIAL_SD, R1          ; card of the settings file
                MOVE    @R1, R1
                CMP     0, R1
                RBRA    _ZXNC_I_SL1, Z
                MOVE    1, R1                   ; 1 = back slot
_ZXNC_I_SL1     MOVE    M2M$RAMROM_DATA, R0
                ADD     4, R0
                CMP     R1, @R0                 ; 4: slot of the image
                RBRA    _ZXNC_I_OLD, Z
                MOVE    ZXN_LOG_CFG_SLT, R8

_ZXNC_I_OFF     SYSCALL(puts, 1)
                MOVE    ZXN_CFG_FH, R0
                MOVE    0, @R0
                RBRA    _ZXNC_I_RET, 1

                ; Remember the settings as they are in the file
_ZXNC_I_OLD     RSUB    _ZXN_CFG_REM, 1
                MOVE    ZXN_LOG_CFG_ON, R8
                SYSCALL(puts, 1)

_ZXNC_I_RET     DECRB
                RET

; Called by OSM_SEL_POST: save the settings if they changed
ZXN_CFG_SAVE    SYSCALL(enter, 1)

                MOVE    ZXN_CFG_FH, R8          ; saving at all?
                CMP     0, @R8
                RBRA    _ZXNC_S_RET, Z

                ; Changed since they were last saved?
                MOVE    M2M$CFM_ADDR, R0
                MOVE    M2M$CFM_DATA, R1
                MOVE    ZXN_CFG_OLD, R2
                XOR     R3, R3
_ZXNC_S_CMP     MOVE    R3, @R0
                CMP     @R1, @R2++
                RBRA    _ZXNC_S_BORROW, !Z
                ADD     1, R3
                CMP     16, R3
                RBRA    _ZXNC_S_CMP, !Z
                RBRA    _ZXNC_S_RET, 1          ; no change

                ; Borrow the card from the core and wait until it is ours
_ZXNC_S_BORROW  MOVE    M2M$RAMROM_DEV, R0
                MOVE    ZXN_IMG_DEV, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    0, @R0
                MOVE    M2M$RAMROM_DATA, R4     ; R4: register 9
                ADD     9, R4
                MOVE    1, @R4
#ifdef ZXN_TEST
                RSUB    ZXN_TEST_GRANT, 1       ; test hook: the core answers
#endif
                MOVE    IO$CYC_MID, R5          ; 1.3 ms per tick
                MOVE    @R5, R6                 ; R6: start
_ZXNC_S_WAIT    MOVE    @R4, R7
                AND     2, R7                   ; granted?
                RBRA    _ZXNC_S_WRITE, !Z
                MOVE    @R5, R7
                SUB     R6, R7                  ; R7: ticks so far
                CMP     ZXN_CFG_TIMEOUT, R7     ; N: timeout > R7
                RBRA    _ZXNC_S_WAIT, N
                MOVE    ZXN_LOG_CFG_TO, R8      ; no grant: give up this time
                SYSCALL(puts, 1)
                RBRA    _ZXNC_S_GIVE, 1

                ; The SD controller buffer holds whatever QNICE read last:
                ; nobody owns it. Seeking to 0 reads the sector of the file.
_ZXNC_S_WRITE   MOVE    ZXN_CFG_FH, R8
                MOVE    @R8, R0                 ; FDH_DEVICE: device handle
                ADD     FAT32$DEV_BUFFERED_FDH, R0
                MOVE    0, @R0
                XOR     R9, R9
                XOR     R10, R10
                SYSCALL(f32_fseek, 1)
                CMP     0, R9
                RBRA    _ZXNC_S_ERR, !Z

                ; One byte per menu line: 1 = selected (as the Shell does)
                MOVE    M2M$CFM_ADDR, R0
                MOVE    M2M$CFM_DATA, R1
                XOR     R2, R2                  ; R2: window
                MOVE    OPTM_ICOUNT, R3
                MOVE    @R3, R3                 ; R3: bytes to write
_ZXNC_S_WIN     MOVE    R2, @R0
                MOVE    1, R5                   ; R5: bit
_ZXNC_S_BIT     XOR     R9, R9
                MOVE    @R1, R6
                AND     R5, R6
                RBRA    _ZXNC_S_BYTE, Z
                MOVE    1, R9
_ZXNC_S_BYTE    SYSCALL(f32_fwrite, 1)
                CMP     0, R9
                RBRA    _ZXNC_S_ERR, !Z
                SUB     1, R3
                RBRA    _ZXNC_S_FLUSH, Z
                AND     0xFFFD, SR              ; clear X
                SHL     1, R5
                RBRA    _ZXNC_S_BIT, !Z
                ADD     1, R2
                RBRA    _ZXNC_S_WIN, 1

_ZXNC_S_FLUSH   SYSCALL(f32_fflush, 1)
                CMP     0, R9
                RBRA    _ZXNC_S_ERR, !Z
                RSUB    _ZXN_CFG_REM, 1
                MOVE    ZXN_LOG_CFG_OK, R8
                SYSCALL(puts, 1)
                RBRA    _ZXNC_S_GIVE, 1

                ; Error: log it and stop saving
_ZXNC_S_ERR     MOVE    ZXN_LOG_CFG_ERR, R8
                SYSCALL(puts, 1)
                MOVE    R9, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                MOVE    ZXN_CFG_FH, R8
                MOVE    0, @R8

                ; Give the card back to the core
_ZXNC_S_GIVE    MOVE    M2M$RAMROM_DEV, R0
                MOVE    ZXN_IMG_DEV, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    0, @R0
                MOVE    M2M$RAMROM_DATA, R0
                ADD     9, R0
                MOVE    0, @R0

_ZXNC_S_RET     SYSCALL(leave, 1)
                RET

; Copy the 16 windows of M2M$CFM_DATA to ZXN_CFG_OLD. Runs in the bank of the
; caller (uses R0 .. R3).
_ZXN_CFG_REM    MOVE    M2M$CFM_ADDR, R0
                MOVE    M2M$CFM_DATA, R1
                MOVE    ZXN_CFG_OLD, R2
                XOR     R3, R3
_ZXNC_R_LOOP    MOVE    R3, @R0
                MOVE    @R1, @R2++
                ADD     1, R3
                CMP     16, R3
                RBRA    _ZXNC_R_LOOP, !Z
                RET

; ----------------------------------------------------------------------------
; Constants and strings
; ----------------------------------------------------------------------------

ZXN_CFG_TIMEOUT .EQU    2300                    ; ticks of 1.3 ms: 3 seconds

ZXN_LOG_CFG_ON  .ASCII_W "ZX Next: settings are saved when they change\n"
ZXN_LOG_CFG_DIR .ASCII_W "ZX Next: real ZX Next SD card, settings are not saved\n"
ZXN_LOG_CFG_SLT .ASCII_W "ZX Next: settings file and image on different cards, settings are not saved\n"
ZXN_LOG_CFG_OK  .ASCII_W "ZX Next: settings saved\n"
ZXN_LOG_CFG_TO  .ASCII_W "ZX Next: SD card busy, settings not saved\n"
ZXN_LOG_CFG_ERR .ASCII_W "ZX Next: settings file error, saving switched off: 0x"
