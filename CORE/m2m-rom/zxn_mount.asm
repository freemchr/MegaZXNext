; ****************************************************************************
; MegaZXNext: ZX Next core for the MEGA65 QNICE ROM: ZX Next SD card image
;
; Included by m2m-rom.asm and by the emulator test test/test_zxn_mount.asm.
; Needs: HANDLE_DEV, WAIT_FOR_SD, ZXN_FH, ZXN_LBA, ZXN_SECTORS and the M2M
; registers M2M$CSR, M2M$RAMROM_DEV, M2M$RAMROM_4KWIN, M2M$RAMROM_DATA.
;
; 32-bit additions: ADD and ADDC must follow each other directly, because
; every ADD (also one that only forms a pointer) changes the carry flag.
;
; MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
; ****************************************************************************
;
; The ZX Next boots from its own SD card. On the MEGA65 this card is an image
; file on the MEGA65 SD card (like MiSTer: boot.vhd). The core (sd_image.vhd)
; reads and writes the sectors of the image directly on the SD card. The
; file may be fragmented: its FAT chain is walked here and every piece
; (extent: first virtual sector, first physical sector) is written to the
; core extent table, at most 512. Then the size, the number of extents and
; the slot go to the device C_DEV_ZXN_IMG (globals.vhd, register map in
; mega65.vhd), "mounted" last, and the core takes over the SD card. QNICE
; must not use the SD card afterwards.
;
; Output: R8 = 0: OK, otherwise pointer to an error message
;         R9 = 0 or error code
; ----------------------------------------------------------------------------

ZXN_MOUNT       INCRB

                MOVE    ZXN_LOG_START, R8
                SYSCALL(puts, 1)

                ; Mount the SD card
                RSUB    WAIT_FOR_SD, 1          ; stability workaround
                MOVE    HANDLE_DEV, R8
                CMP     0, @R8                  ; already mounted?
                RBRA    _ZXNM_OPEN, !Z          ; yes
                MOVE    1, R9                   ; partition #1
                SYSCALL(f32_mnt_sd, 1)
                CMP     0, R9                   ; R9 = error code
                RBRA    _ZXNM_OPEN, Z
                MOVE    HANDLE_DEV, R8          ; not mounted
                MOVE    0, @R8
                MOVE    ZXN_ERR_MOUNT, R8
                RBRA    _ZXNM_RET, 1

                ; Open the image
_ZXNM_OPEN      MOVE    ZXN_PATH_VHD, R10
                RSUB    _ZXN_FOPEN, 1
                CMP     0, R10
                RBRA    _ZXNM_SIZE, Z
                MOVE    ZXN_PATH_IMG, R10
                RSUB    _ZXN_FOPEN, 1
                CMP     0, R10
                RBRA    _ZXNM_SIZE, Z
                MOVE    R10, R9
                MOVE    ZXN_ERR_NOFILE, R8
                RBRA    _ZXNM_RET, 1

                ; Size in sectors: R3|R2 (a VHD footer is part of it)
_ZXNM_SIZE      MOVE    ZXN_FH, R0
                ADD     FAT32$FDH_SIZE_LO, R0   ; SIZE_HI follows SIZE_LO
                MOVE    @R0++, R8
                MOVE    @R0, R9
                MOVE    512, R10
                XOR     R11, R11
                SYSCALL(divu32, 1)              ; R9|R8 = size / 512
                MOVE    R8, R2
                MOVE    R9, R3
                MOVE    ZXN_SECTORS, R0
                MOVE    R2, @R0++
                MOVE    R3, @R0
                MOVE    R2, R0
                OR      R3, R0
                RBRA    _ZXNM_CLUS, !Z
                MOVE    ZXN_ERR_EMPTY, R8
                XOR     R9, R9
                RBRA    _ZXNM_RET, 1

                ; Number of clusters: R5|R4 = ceil(sectors / sectors per cluster)
_ZXNM_CLUS      MOVE    HANDLE_DEV, R0
                ADD     FAT32$DEV_SECT_PER_CLUS, R0
                MOVE    @R0, R1                 ; R1: sectors per cluster
                MOVE    R2, R8
                MOVE    R3, R9
                MOVE    R1, R10
                XOR     R11, R11
                SYSCALL(divu32, 1)              ; R9|R8 quotient, R11|R10 rest
                OR      R11, R10
                RBRA    _ZXNM_NCL, Z
                ADD     1, R8
                ADDC    0, R9
_ZXNM_NCL       MOVE    R8, R4
                MOVE    R9, R5

                ; First cluster: R7|R6
                MOVE    ZXN_FH, R0
                ADD     FAT32$FDH_START_CLUS_LO, R0     ; HI follows LO
                MOVE    @R0++, R6
                MOVE    @R0, R7

                ; Extents: the pieces of the file on the card. Walk the FAT
                ; chain; wherever the next cluster is not cluster + 1, a new
                ; extent starts. Every extent goes into the core extent
                ; table right away (C_DEV_ZXN_IMG registers 0x10 .. 0x14).
                ; R7|R6 = cluster, R5|R4 = FAT entries still to follow,
                ; R3|R2 = FAT sector, R1 = index of the entry in the sector
                MOVE    ZXN_NCLUS, R0           ; remember the cluster count
                MOVE    R4, @R0++
                MOVE    R5, @R0
                MOVE    ZXN_SPC, R0             ; and the sectors per cluster
                MOVE    R1, @R0
                MOVE    ZXN_NEXT, R0            ; no extents yet
                MOVE    0, @R0

                MOVE    M2M$RAMROM_DEV, R0      ; select the core device
                MOVE    ZXN_IMG_DEV, @R0
                MOVE    M2M$RAMROM_4KWIN, R0
                MOVE    0, @R0
                MOVE    M2M$RAMROM_DATA, R0     ; not mounted while we write
                ADD     5, R0
                MOVE    0, @R0

                SUB     1, R4                   ; N clusters: N - 1 entries
                SUBC    0, R5

                XOR     R8, R8                  ; first extent: virtual 0
                XOR     R9, R9
                RSUB    _ZXN_NEWEXT, 1          ; R8 = 0 or error message
                CMP     0, R8
                RBRA    _ZXNM_ERR, !Z
                RSUB    _ZXN_SEEKFAT, 1         ; R8 = 0 or SD error code
                CMP     0, R8
                RBRA    _ZXNM_RDERR, !Z

_ZXNM_LOOP      MOVE    R4, R0                  ; all entries followed?
                OR      R5, R0
                RBRA    _ZXNM_DONE, Z

                CMP     128, R1                 ; next FAT sector?
                RBRA    _ZXNM_ENTRY, !Z
                XOR     R1, R1
                ADD     1, R2
                ADDC    0, R3
                RSUB    _ZXN_RDFAT, 1
                CMP     0, R8
                RBRA    _ZXNM_RDERR, !Z

_ZXNM_ENTRY     MOVE    R1, R0                  ; byte offset = index * 4
                ADD     R0, R0
                ADD     R0, R0
                RSUB    _ZXN_RDW, 1
                MOVE    R8, R10                 ; R10: low word of the entry
                RSUB    _ZXN_RDW, 1
                AND     0x0FFF, R8              ; R8: high word (28 bit FAT)
                MOVE    R6, R11                 ; R12|R11: cluster + 1
                MOVE    R7, R12
                ADD     1, R11
                ADDC    0, R12
                CMP     R11, R10
                RBRA    _ZXNM_JUMP, !Z
                CMP     R12, R8
                RBRA    _ZXNM_JUMP, !Z
                MOVE    R11, R6                 ; next cluster: same extent
                MOVE    R12, R7
                ADD     1, R1
                SUB     1, R4
                SUBC    0, R5
                RBRA    _ZXNM_LOOP, 1

                ; The chain jumps to cluster R8|R10: a new extent. Its index
                ; in the file is N - (entries still to follow). A valid
                ; cluster is 2 .. 0x0FFFFFF6 (end of chain, bad: corrupt)
_ZXNM_JUMP      MOVE    R10, R6                 ; R7|R6: new cluster
                MOVE    R8, R7
                CMP     0x0FFF, R7
                RBRA    _ZXNM_JCHK, !Z
                CMP     0xFFF6, R6              ; N: 0xFFF6 > R6
                RBRA    _ZXNM_CORRUPT, !N
                RBRA    _ZXNM_JOK, 1
_ZXNM_JCHK      CMP     0, R7
                RBRA    _ZXNM_JOK, !Z
                CMP     2, R6                   ; N: 2 > R6
                RBRA    _ZXNM_CORRUPT, N

_ZXNM_JOK       MOVE    ZXN_NCLUS, R0           ; R9|R8 = N - entries left
                MOVE    @R0++, R8
                MOVE    @R0, R9
                SUB     R4, R8
                SUBC    R5, R9
                MOVE    ZXN_SPC, R0             ; * sectors per cluster
                MOVE    @R0, R10
                XOR     R11, R11
                SYSCALL(mulu32, 1)              ; R9|R8 = first virtual sector
                RSUB    _ZXN_NEWEXT, 1
                CMP     0, R8
                RBRA    _ZXNM_ERR, !Z
                SUB     1, R4                   ; this entry is followed
                SUBC    0, R5
                RSUB    _ZXN_SEEKFAT, 1
                CMP     0, R8
                RBRA    _ZXNM_RDERR, !Z
                RBRA    _ZXNM_LOOP, 1

_ZXNM_RDERR     MOVE    R8, R9
                MOVE    ZXN_ERR_READ, R8
                RBRA    _ZXNM_RET, 1

                ; Log the broken chain: cluster index, entry
_ZXNM_CORRUPT   MOVE    ZXN_LOG_CORRUPT, R8
                SYSCALL(puts, 1)
                MOVE    R7, R8
                SYSCALL(puthex, 1)
                MOVE    R6, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                MOVE    ZXN_ERR_CORRUPT, R8
_ZXNM_ERR       XOR     R9, R9
                RBRA    _ZXNM_RET, 1

                ; The SD controller buffer no longer holds a sector of any
                ; open file
_ZXNM_DONE      MOVE    HANDLE_DEV, R0
                ADD     FAT32$DEV_BUFFERED_FDH, R0
                MOVE    0, @R0

                ; Slot that holds the image: 1 = back slot, 0 = bottom tray
                MOVE    M2M$CSR, R0
                MOVE    @R0, R1
                AND     M2M$CSR_SD_ACTIVE, R1
                RBRA    _ZXNM_SLOT, Z
                MOVE    1, R1

                ; Hand the image over to the core: mounted is written last
_ZXNM_SLOT      MOVE    M2M$RAMROM_DATA, R0
                ADD     2, R0
                MOVE    ZXN_SECTORS, R2
                MOVE    @R2++, @R0++            ; 2, 3: size low, high
                MOVE    @R2, @R0++
                MOVE    R1, @R0++               ; 4: slot
                MOVE    M2M$RAMROM_DATA, R2
                ADD     7, R2
                MOVE    ZXN_NEXT, R3
                MOVE    @R3, @R2                ; 7: number of extents
                MOVE    1, @R0                  ; 5: mounted

                ; Log: first sector, size, extents, slot
                MOVE    ZXN_LOG_LBA, R8
                SYSCALL(puts, 1)
                MOVE    ZXN_LBA, R0
                MOVE    @R0++, R2
                MOVE    @R0, R8
                SYSCALL(puthex, 1)
                MOVE    R2, R8
                SYSCALL(puthex, 1)
                MOVE    ZXN_LOG_SIZE, R8
                SYSCALL(puts, 1)
                MOVE    ZXN_SECTORS, R0
                MOVE    @R0++, R2
                MOVE    @R0, R8
                SYSCALL(puthex, 1)
                MOVE    R2, R8
                SYSCALL(puthex, 1)
                MOVE    ZXN_LOG_EXT, R8
                SYSCALL(puts, 1)
                MOVE    ZXN_NEXT, R0
                MOVE    @R0, R8
                SYSCALL(puthex, 1)
                MOVE    ZXN_LOG_SLOT, R8
                SYSCALL(puts, 1)
                MOVE    R1, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)

                XOR     R8, R8
                XOR     R9, R9

_ZXNM_RET       DECRB
                RET

; New extent: first virtual sector R9|R8, first cluster R7|R6 (caller). The
; physical sector is cluster start LBA + (cluster - 2) * sectors per cluster;
; the first extent is also logged as ZXN_LBA. Output: R8 = 0 or error message.
; Runs in the bank of the caller (uses R0, R8 .. R11).
_ZXN_NEWEXT     MOVE    M2M$RAMROM_DATA, R0
                ADD     0x10, R0
                MOVE    R8, @R0++               ; 0x10, 0x11: virtual
                MOVE    R9, @R0++
                MOVE    ZXN_NEXT, R8            ; table full?
                CMP     ZXN_EXT_MAX, @R8
                RBRA    _ZXN_NE_OK, !Z
                MOVE    ZXN_ERR_MANY, R8
                RET
_ZXN_NE_OK      MOVE    R6, R8
                MOVE    R7, R9
                SUB     2, R8
                SUBC    0, R9
                MOVE    ZXN_SPC, R10
                MOVE    @R10, R10
                XOR     R11, R11
                SYSCALL(mulu32, 1)              ; R9|R8 = low 32 bits
                MOVE    HANDLE_DEV, R10         ; CLUSTER_HI follows CLUSTER_LO
                ADD     FAT32$DEV_CLUSTER_LO, R10
                ADD     @R10++, R8              ; ADD and ADDC back to back:
                ADDC    @R10, R9                ; nothing in between may touch C
                MOVE    R8, @R0++               ; 0x12, 0x13: physical
                MOVE    R9, @R0++
                MOVE    ZXN_NEXT, R10           ; 0x14: store as entry n
                MOVE    @R10, @R0
                MOVE    ZXN_NEXT, R10
                CMP     0, @R10                 ; first extent: remember it
                RBRA    _ZXN_NE_CNT, !Z
                MOVE    ZXN_LBA, R11
                MOVE    R8, @R11++
                MOVE    R9, @R11
_ZXN_NE_CNT     ADD     1, @R10
#ifdef ZXN_TEST
                RSUB    ZXN_TEST_EXT, 1         ; test hook: log the extent
#endif
                XOR     R8, R8
                RET

; Read the FAT sector of cluster R7|R6 (caller) and set R3|R2 (FAT sector)
; and R1 (index of the entry); output: R8 = 0 or error code. Runs in the bank
; of the caller.
_ZXN_SEEKFAT    MOVE    R6, R8                  ; 128 entries per FAT sector
                MOVE    R7, R9
                MOVE    128, R10
                XOR     R11, R11
                SYSCALL(divu32, 1)
                MOVE    R10, R1
                MOVE    HANDLE_DEV, R0          ; FAT_HI follows FAT_LO
                ADD     FAT32$DEV_FAT_LO, R0
                ADD     @R0++, R8
                ADDC    @R0, R9
                MOVE    R8, R2
                MOVE    R9, R3
                RSUB    _ZXN_RDFAT, 1
                RET

; Open the file R10 as ZXN_FH; output: R10 = 0 or error code
_ZXN_FOPEN      MOVE    HANDLE_DEV, R8
                MOVE    ZXN_FH, R9
                XOR     R11, R11
                SYSCALL(f32_fopen, 1)
                RET

; Read the FAT sector R3|R2 into the SD controller buffer; output: R8 = 0 or
; error code. Runs in the bank of the caller.
_ZXN_RDFAT      MOVE    R2, R8
                MOVE    R3, R9
                SYSCALL(sd_r_block, 1)
                RET

; Little endian word at offset R0 of the SD controller buffer: R8 = word,
; R0 = R0 + 2. Runs in the bank of the caller.
_ZXN_RDW        MOVE    R0, R8
                SYSCALL(sd_r_byte, 1)
                MOVE    R8, R9                  ; low byte
                MOVE    R0, R8
                ADD     1, R8
                SYSCALL(sd_r_byte, 1)
                SWAP    R8, R8                  ; high byte
                OR      R9, R8
                ADD     2, R0
                RET

; ----------------------------------------------------------------------------
; Constants and strings
; ----------------------------------------------------------------------------

ZXN_IMG_DEV     .EQU    0x0100                  ; C_DEV_ZXN_IMG in globals.vhd
ZXN_EXT_MAX     .EQU    512                     ; size of the extent table

ZXN_PATH_VHD    .ASCII_W "/ZXNEXT/BOOT.VHD"
ZXN_PATH_IMG    .ASCII_W "/ZXNEXT/BOOT.IMG"

ZXN_LOG_START   .ASCII_W "ZX Next: mounting the SD card image\n"
ZXN_LOG_LBA     .ASCII_W "ZX Next: image at sector 0x"
ZXN_LOG_SIZE    .ASCII_W ", sectors 0x"
ZXN_LOG_SLOT    .ASCII_W ", slot "
ZXN_LOG_EXT     .ASCII_W ", extents 0x"
ZXN_LOG_CORRUPT .ASCII_W "ZX Next: broken FAT chain, next cluster 0x"

ZXN_ERR_MOUNT   .ASCII_P "Cannot mount the SD card.\n\n"
ZXN_HELP        .ASCII_P "The ZX Next needs an image of its\n"
                .ASCII_P "SD card on the MEGA65 SD card\n"
                .ASCII_P "(FAT32), for example the boot.vhd of\n"
                .ASCII_P "the MiSTer core:\n\n"
                .ASCII_P "   /zxnext/boot.vhd   or\n"
                .ASCII_W "   /zxnext/boot.img\n"
ZXN_ERR_NOFILE  .ASCII_P "ZX Next SD card image not found.\n\n"
                .ASCII_P "Copy the image of a ZX Next\n"
                .ASCII_P "SD card to the MEGA65 SD card as\n\n"
                .ASCII_P "   /zxnext/boot.vhd   or\n"
                .ASCII_W "   /zxnext/boot.img\n"
ZXN_ERR_EMPTY   .ASCII_W "The ZX Next SD card image is empty.\n"
ZXN_ERR_READ    .ASCII_W "Error while reading the SD card.\n"
ZXN_ERR_MANY    .ASCII_P "The ZX Next SD card image is in more\n"
                .ASCII_P "than 512 pieces on the SD card. Copy\n"
                .ASCII_P "it again onto a freshly formatted\n"
                .ASCII_W "card or defragment the card.\n"
ZXN_ERR_CORRUPT .ASCII_P "The FAT chain of the ZX Next SD card\n"
                .ASCII_W "image is broken. Check the SD card.\n"

; This needs to be the last thing before the "Variables" sections starts
