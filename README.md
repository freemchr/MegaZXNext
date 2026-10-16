ZX Spectrum Next for MEGA65
===========================

A port of the [ZX Spectrum Next](https://www.specnext.com/) core to the
[MEGA65](https://mega65.org/), based on the MiSTer core
[ZXNext_MiSTer](https://github.com/MiSTer-devel/ZXNext_MISTer) and built on the
[MiSTer2MEGA65](https://github.com/sy2002/MiSTer2MEGA65) framework.

The ZX Spectrum Next is an enhanced ZX Spectrum: a Z80N CPU at 3.5, 7, 14 or 28 MHz,
Layer 2 bitmap graphics, tilemap, sprites, copper, DMA, three AY sound chips, DivMMC and
Multiface, and 2 MB of RAM. It runs NextZXOS and the classic Spectrum 48K, 128K and +3 software.

Status: alpha, MEGA65 R6 only
-----------------------------

**V0.2 alpha** has been tested on a MEGA65 **R6**: NextZXOS boots, its menus, 48K BASIC and
the Browser work, music plays, and Next games (Warhawk Next, Nextoid) run with keyboard
control. Expect bugs, and please report them (see below).

* **R4 and R5:** the core builds for them, but nobody has tested it on these boards yet. If you
  have one, a test report is very welcome.
* **R3 / R3A is not supported:** the ZX Next's RAM lives in the SDRAM, which the R3 does not have.

Requirements
------------

* A MEGA65 R6 (R4/R5 untested, see above).
* An SD card in the MEGA65 (FAT32) with an **image of a ZX Next SD card** on it. No ROMs or
  system files are included in this core: the ZX Next loads its firmware, ROMs and NextZXOS
  from that image, just like the real machine loads them from its SD card.

Installation
------------

1. **The ZX Next SD card image.** Use one of:
   * the `boot.vhd` of the MiSTer core (in the `releases` folder of
     [ZXNext_MiSTer](https://github.com/MiSTer-devel/ZXNext_MISTer)), or
   * an image file of a ZX Next SD card with the System/Next distribution (tested: 24.11).

   Copy it to the MEGA65's SD card as **`/zxnext/boot.vhd`** or **`/zxnext/boot.img`**. The
   file does not need to be contiguous (up to 512 fragments are fine).
2. **The core.** Flash the `.cor` file of the release into a core slot with the MEGA65's flash
   menu (switch the MEGA65 on while holding **No Scroll**), as described in the MEGA65 user guide.
3. Start the core. The welcome screen shows the most important keys; press Space and the
   ZX Next boots.

Keyboard
--------

| MEGA65 key            | ZX Next                    |
|-----------------------|----------------------------|
| Shift                 | Caps Shift                 |
| Ctrl, MEGA            | Symbol Shift               |
| Alt                   | Extend Mode                |
| Caps Lock             | Caps Lock                  |
| No Scroll             | Graph                      |
| Tab / Clr Home        | True Video / Inv Video     |
| Esc, Run/Stop         | Break                      |
| ← (left of 1)         | Edit                       |
| Inst/Del              | Delete                     |
| Cursor keys           | Cursor keys                |
| `: + - * / = @ £ ^`   | the matching Symbol Shift combinations |
| F3                    | 50 Hz / 60 Hz              |
| F9                    | Multiface NMI              |
| F11                   | DivMMC NMI (drive button)  |
| F13                   | Next CPU speed (3.5 → 7 → 14 → 28 MHz) |
| Help                  | Options menu               |

The reset button: a short press is a soft reset (back to the NextZXOS menu), a long press a
hard reset (reloads the firmware). **Reset ZX Next** in the options menu is a soft reset, too.

Joysticks
---------

MEGA65 port 1 is the ZX Next's left joystick, port 2 its right joystick (**Flip joystick ports**
in the options menu swaps them). What a joystick does is a setting of the ZX Next, not of the
core. With the settings of the standard distribution the left joystick is **Cursor** (it moves
through the NextZXOS menus) and the right one is **Sinclair 2** (it acts as the keys 1 to 5). Most
games want **Kempston**: change the joystick modes in the ZX Next setup (press Space while the
firmware boots) or in `/machines/next/config.ini` of the image. One fire button is supported.

Options menu
------------

Press **Help** for the options menu: HDMI mode (720p, 576p, 640x480, 720x480, 800x600), VGA
mode (standard or 15 kHz retro), flip joystick ports, HDMI CRT emulation, audio improvements,
Reset ZX Next and the help pages. The settings are not saved: the ZX Next owns the SD card while it runs.

Known issues
------------

* Only tested on R6. R4/R5 are untested.
* Now and then the core stops at a grey screen during boot. A reset (or switching off and on)
  gets it going. Not seen since the CPU speed fix, but not proven gone.
* No mouse: the ZX Next's (PS/2) mouse is not connected to the MEGA65's mouse.
* The boot screen of the ZX Next firmware says "MiSTer Next" (the firmware chooses it by the
  machine ID the core reports).
* Tape files (.TAP) and +3 disk images (.DSK) have not been tested yet.

Reporting issues
----------------

Please open an issue at https://github.com/freemchr/MegaZXNext/issues with your MEGA65 board
revision (R4/R5/R6), the image you use, and what you did.

Building
--------

See [AGENTS.md](AGENTS.md) for the layout of the repository, how to build the bitstream with
Vivado and how to run the simulations.

Credits and license
-------------------

ZX Spectrum Next core by Alvin Albrecht, Victor Trucco and Fabio Belavenuto; MiSTer port by
Sorgelig and the MiSTer team; MiSTer2MEGA65 by sy2002 and MJoergen. MEGA65 port by Chris
Freeman. See [AUTHORS](AUTHORS) for everything this core uses.

The core is licensed under the GNU GPL v3 (see [LICENSE](LICENSE)). Parts of it are licensed
under other free software licenses, as stated in the source files.
