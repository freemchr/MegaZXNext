Version 0.1 alpha - October 2026
================================

First test release of the ZX Spectrum Next for the MEGA65, for the MEGA65 **R6**.
Based on ZXNext_MiSTer (ZX Next core 3.02.00, matches System/Next 24.11) and
MiSTer2MEGA65 V2.0.1.

Tested on an R6: NextZXOS boots from the SD card image, its menus, 48K BASIC and the
Browser work, music plays, Warhawk Next and Nextoid run with keyboard control.
R4 and R5 builds are untested.

Features (implemented; not all of them tested yet)
---------------------------------------------------

* The ZX Next's SD card is an image file on the MEGA65's SD card: `/zxnext/boot.vhd` (e.g.
  MiSTer's boot.vhd) or `/zxnext/boot.img`. The file may be fragmented (up to 512 pieces).
* 2 MB of ZX Next RAM in the MEGA65's SDRAM (R4/R5/R6).
* All CPU speeds: 3.5, 7, 14 and 28 MHz (F13 cycles them).
* MEGA65 keyboard mapped to the ZX Next keyboard, including the Next's extra keys;
  F3 50/60 Hz, F9 Multiface, F11 DivMMC NMI.
* HDMI (720p, 576p, 640x480, 720x480, 800x600) and VGA (standard or 15 kHz retro),
  HDMI CRT emulation, audio filters, joysticks in both ports (can be swapped).
* Real-time clock from the MEGA65.

Fixed during the bring-up (not in the MiSTer core)
---------------------------------------------------

* A CPU speed change could lose the opcode fetch that straddled the switch. NextZXOS then
  showed a black screen in 48K BASIC and the Browser. MiSTer's clock switch has the same
  window; this core keeps the CPU clock still for a moment after every speed change.

Known issues
------------

* R4 and R5 untested.
* An occasional grey screen at boot (a reset helps); not seen since the CPU speed fix.
* No mouse support.
* The firmware's boot screen says "MiSTer Next".
* Tape (.TAP) and +3 disk (.DSK) loading untested.
* The options menu settings are not saved (the ZX Next owns the SD card while it runs).

The MiSTer2MEGA65 framework changelog is at
https://github.com/sy2002/MiSTer2MEGA65/blob/master/VERSIONS.md
