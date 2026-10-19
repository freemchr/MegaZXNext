Version 1.1 - October 2026
==========================

V1.0 plus remembered settings, and the R3/R3A build (1 MB) is now part of the release: a tester
reported the R3 test build working like the R6 version.

* **The options menu settings are remembered** (requested by testers): copy `release/zxnext/zxncfg`
  to the MEGA65's SD card as `/zxnext/zxncfg`. The settings are loaded at startup and saved after
  every change. While the file is written, the core lends the SD card back to the M2M Shell: the
  ZX Next finishes its current sector and waits for a moment. Only with an image file; with a real
  ZX Next SD card the settings are loaded but not saved. Tested on the R6.
* **R3 / R3A** (`megazxnext_r3.cor`): 1 MB of RAM (see the R3 test build below). Tested on an R3
  (without the settings file); not yet on an R3A.
* R4 and R5: still untested.

Known issues: as V1.0, plus: a real ZX Next SD card in the bottom tray was reported not to boot
(use the back slot); settings are not saved with a real ZX Next SD card.

R3 / R3A test build (1 MB) - October 2026
==========================================

A separate test build of V1.0 for the MEGA65 **R3 / R3A** (`megazxnext_r3.cor`). The R3 has no
SDRAM, so the ZX Next gets **1 MB of RAM in the FPGA's block RAM** (`bram_zxn.vhd`), the memory
of an unexpanded ZX Next: NextZXOS shows 768K. Addresses above 1 MB read as 0xFF and ignore
writes, so NextZXOS's RAM test sees a 1 MB machine. The R3 board top routes the SD cards through
the core as on R4-R6. R4, R5 and R6 are unchanged (their SDRAM constraints moved to
`CORE/CORE-SDRAM.xdc`).

Tested on an R6 with the same block RAM instead of the SDRAM: NextZXOS boots, `.MEM` shows 768K,
Warhawk Next runs.

**Tested on an R3** by a tester: works like the R6 version. HDMI modes, VGA, scanlines, booting
from `/zxnext/boot.vhd` and from a real ZX Next SD card in the back slot, Reset ZX Next,
joysticks and many games work. Software that needs 2 MB (e.g. RogueCraft DX) returns to the
NextZXOS menu, as expected with 1 MB. A real ZX Next card in the bottom tray was reported not to
boot (use the back slot). Requested: a settings file for the options menu.

Version 1.0 - October 2026
==========================

First full release of **MegaZXNext**, a ZX Next core for the MEGA65, for the MEGA65 **R6**,
with test builds for **R4** and **R5**. Based on ZXNext_MiSTer (ZX Next core 3.02.00, matches
System/Next 24.11) and MiSTer2MEGA65 V2.0.1.

Version 1.0 is the V0.3 test build (below) plus support for real ZX Next SD cards. The V0.3 build was reported working on an R6, with the grey screen
of V0.2 gone. R4 and R5 have not been tested: if you have one, please report how it went.

* Renamed to **MegaZXNext** ("a ZX Next core for the MEGA65"): the System/Next licence does
  not allow systems built from the ZX Next's VHDL to be called "ZX Spectrum Next". Welcome
  screen, help, options menu and core name changed.
* **Grey screen fixed:** at 112 MHz the SDRAM read data was sampled just after the end of its
  valid window (hold slack -0.9 ns against the SDRAM datasheet), so reads could return wrong
  bytes depending on the chip and temperature, and the ZX Next stopped at a grey screen after
  some resets. The SDRAM clock pin now runs 1.4 ns later (PLL), and the SDRAM I/O timing is
  constrained, so Vivado checks the margins on every build.
* **Real ZX Next SD cards:** besides an image file, the core can now use a real ZX Next SD card
  (FAT32) directly, for example the card from a real ZX Spectrum Next. It is used when the card
  has no `/zxnext/boot.vhd` or `/zxnext/boot.img` but has `/TBBLUE.FW` in its root; the ZX
  Next's SPI then goes straight to the card. FAT16 cards are not supported. Not yet tested on
  hardware.
* The welcome and help screens say which card is used: the one in the back slot if a card is in
  it, otherwise the one in the bottom tray.

Not tested yet (please report): a real ZX Next SD card, VGA output, F13 (CPU speed), the NMI keys F9/F11, +3 disk images
(.DSK), the **Reset ZX Next** menu item, R4 and R5.

Known issues: no mouse; joystick modes are ZX Next settings stored in the image (see the README),
one fire button only; the firmware's boot screen says "MiSTer Next"; the options menu settings
are not saved.

Version 0.3 alpha - October 2026
================================

Test build, not released: the SDRAM read timing fix and the rename to MegaZXNext (see 1.0).

Version 0.2 alpha - October 2026
================================

First test release of the ZX Next core for the MEGA65 (released as "ZX Spectrum Next for
MEGA65"), for the MEGA65 **R6**.
Based on ZXNext_MiSTer (ZX Next core 3.02.00, matches System/Next 24.11) and
MiSTer2MEGA65 V2.0.1.

Tested on an R6: NextZXOS boots from the SD card image, its menus, 48K BASIC and the
Browser work, music plays, Warhawk Next and Nextoid run with keyboard control, a .TAP game
(Dizzy) loads, and a joystick in port 2 reads correctly as Kempston (all directions and fire).
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
* "Reset ZX Next" in the options menu (soft reset, like a short press of the reset button).

Fixed during the bring-up (not in the MiSTer core)
---------------------------------------------------

* A CPU speed change could lose the opcode fetch that straddled the switch. NextZXOS then
  showed a black screen in 48K BASIC and the Browser. MiSTer's clock switch has the same
  window; this core keeps the CPU clock still for a moment after every speed change.

Known issues
------------

* R4 and R5 untested.
* Now and then the ZX Next stops at a grey screen after a reset. Another reset gets it going;
  sometimes it takes a couple (a long press of the reset button helps).
* No mouse support.
* Joystick modes are ZX Next settings, not core settings: depending on your image, the
  joystick may act as Cursor or Sinclair keys. Most games want Kempston (see the README).
  One fire button only.
* The firmware's boot screen says "MiSTer Next".
* +3 disk images (.DSK) untested.
* The options menu settings are not saved (the ZX Next owns the SD card while it runs).

Version 0.1 alpha - September 2026
==================================

First build, published before it had run on a MEGA65 (no SD card image support yet).
Superseded by V0.2 alpha; do not use it.

The MiSTer2MEGA65 framework changelog is at
https://github.com/sy2002/MiSTer2MEGA65/blob/master/VERSIONS.md
