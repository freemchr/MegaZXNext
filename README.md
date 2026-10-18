MegaZXNext
==========

[![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-cjf077-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/cjf077)

A ZX Next core for the [MEGA65](https://mega65.org/): a port of the open source
[ZX Spectrum Next](https://www.specnext.com/) FPGA core, based on the MiSTer core
[ZXNext_MiSTer](https://github.com/MiSTer-devel/ZXNext_MISTer) and built on the
[MiSTer2MEGA65](https://github.com/sy2002/MiSTer2MEGA65) framework.

MegaZXNext is not a ZX Spectrum Next and is not made or endorsed by SpecNext Ltd. The licence of
the System/Next distribution does not allow systems built from the ZX Next's VHDL to be called
"ZX Spectrum Next"; "Sinclair" and "ZX Spectrum" are trademarks of their owners.

The ZX Next is an enhanced ZX Spectrum: a Z80N CPU at 3.5, 7, 14 or 28 MHz,
Layer 2 bitmap graphics, tilemap, sprites, copper, DMA, three AY sound chips, DivMMC and
Multiface, and 2 MB of RAM. It runs NextZXOS and the classic Spectrum 48K, 128K and +3 software.

Status: V1.0, tested on the MEGA65 R6
-------------------------------------

**V1.0** runs on a MEGA65 **R6**: NextZXOS boots, its menus, 48K BASIC and the Browser work,
music plays, Next games (Warhawk Next, Nextoid) run with keyboard control, tape (.TAP) games
load, and a joystick reads correctly as Kempston. The grey screen that V0.2 alpha sometimes
showed after a reset is fixed (it was an SDRAM read timing problem). Please report bugs (see
below).

* **R4 and R5:** the core builds for them, but nobody has tested it on these boards yet. If you
  have one, a test report is very welcome.
* **R3 / R3A is not supported.** The ZX Next needs 2 MB of fast RAM. On the R4, R5 and R6 that
  RAM is the board's SDRAM chip, which the R3 and R3A do not have. Their other memory, the
  HyperRAM, is too slow for a CPU running at up to 28 MHz, and the MEGA65 framework already uses
  it for the HDMI picture. An R3 version with 1 MB (like an unexpanded ZX Next) held in the
  FPGA's own memory may be possible later; it has not been built or tested.

Requirements
------------

* A MEGA65 R6 (R4/R5 untested, see above).
* Either an **image of a ZX Next SD card** on the MEGA65's SD card (FAT32), or a **real ZX Next
  SD card** (FAT32) in one of the MEGA65's SD card slots. No ROMs or system files are included
  in this core: the ZX Next loads its firmware, ROMs and NextZXOS from that card, just like the
  real machine does.

What goes on the SD card
------------------------

There are two ways to give the ZX Next its SD card:

1. **An image file** (recommended): a byte-for-byte copy of a complete ZX Next SD card, stored on
   the MEGA65's normal SD card next to everything else. The ZX Next only ever touches that file.
2. **A real ZX Next SD card** (new in V1.0, not yet tested on hardware): a FAT32 card prepared
   for the ZX Next, for example the card from a real ZX Spectrum Next, put into the MEGA65. The
   core uses it when the card has no image on it but has `/TBBLUE.FW` in its root. The ZX Next
   then reads and writes the card directly, as on a real Next. FAT16 cards are not supported
   (the MEGA65 needs to read the card at startup): copy the files of a FAT16 card onto a FAT32
   card.

### Which SD card is used

The core uses **one** SD card, chosen once when it starts:

1. The card in the **back slot**, if one is inserted.
2. Otherwise the card in the **bottom tray**.

On that card it looks first for `/zxnext/boot.vhd`, then `/zxnext/boot.img`. If neither is
there but `/TBBLUE.FW` is, it uses the card itself as a real ZX Next card. The other slot is not
used at all.

| Back slot | Bottom tray | What the ZX Next uses |
|---|---|---|
| empty | MEGA65 card with `/zxnext/boot.img` | the image on the bottom tray card |
| MEGA65 card with `/zxnext/boot.img` | anything | the image on the back slot card |
| real ZX Next card | MEGA65 card | the real ZX Next card (the tray card is not used) |
| empty | real ZX Next card | the real ZX Next card |

Don't swap or remove cards while the core is running: switch the MEGA65 off first.

### The image file

The MEGA65 SD card (FAT32) needs one file:

| Path on the MEGA65 SD card | What it is |
|---|---|
| `/zxnext/boot.vhd` or `/zxnext/boot.img` | an image (a byte-for-byte copy) of a complete ZX Next SD card |

### What the ZX Next needs

Inside the image (or on the real ZX Next card), the ZX Next expects the **System/Next distribution**, exactly as on a real
ZX Spectrum Next. The files it needs at a minimum:

| Path inside the image | What it is |
|---|---|
| `/TBBLUE.FW` | the ZX Next firmware (boot menu, loads the ROMs) |
| `/machines/next/` | the ROMs (`enNextZX.rom` NextZXOS ROM, `enNxtmmc.rom` DivMMC ROM, `48.rom`, `128.rom`, `plus3.rom`, ...), keymaps and `config.ini` (machine settings) |
| `/nextzxos/`, `/sys/`, `/dot/` | NextZXOS and its system files and dot commands |

Everything else in the distribution (`/games`, `/apps`, `/demos`, `/docs`, ...) is optional
but recommended. `TBBLUE.TBU` (FPGA core updates for a real Next) is not used.

**These files are not provided here.** The ROMs, the firmware and NextZXOS are copyrighted by
their owners (among others: the Sinclair ZX Spectrum ROMs © Amstrad / Sky plc, NextZXOS and
NextBASIC © Garry Lancaster, TBBlue © Victor Trucco and Fabio Belavenuto, System/Next ©
SpecNext Ltd; see the distribution's `README.md` and `LICENSE.md`). This repository and its
releases contain only the FPGA core. Get the files from their official sources:

* the **System/Next distribution**, free from SpecNext Ltd (https://www.specnext.com), or
* the **`boot.vhd`** of the MiSTer core (in the `releases` folder of
  [ZXNext_MiSTer](https://github.com/MiSTer-devel/ZXNext_MISTer)): a ready-made image with an
  older distribution.

To make an image with the current distribution, prepare a ZX Next SD card the official way (a
FAT32 card with the distribution unzipped onto it), then copy the whole card into an image file
(e.g. `dd` on Linux/macOS, Win32 Disk Imager on Windows). Tested: System/Next 24.11 in a
2 GB image.

Installation
------------

1. **The ZX Next SD card image** (see above). Use one of:
   * the `boot.vhd` of the MiSTer core (in the `releases` folder of
     [ZXNext_MiSTer](https://github.com/MiSTer-devel/ZXNext_MISTer)), or
   * an image file of a ZX Next SD card with the System/Next distribution (tested: 24.11).

   Copy it to the MEGA65's SD card as **`/zxnext/boot.vhd`** or **`/zxnext/boot.img`**. The
   file does not need to be contiguous (up to 512 fragments are fine). Remember: a card in the
   back slot is used before the card in the bottom tray (see "Which SD card is used" above).

   Or use a **real ZX Next SD card** (FAT32, `/TBBLUE.FW` in its root) instead: put it into the
   back slot (see "Which SD card is used" above).
2. **The core.** Take the `.cor` file for your board from the release (`megazxnext_r6.cor`
   for an R6; `_r5`/`_r4` are untested; `megazxnext_v1.0_r4_r5_r6.zip` has all three) and flash it into a core slot with the MEGA65's flash
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
core, and it depends on your image: a joystick may act as **Cursor** keys (it moves through the
NextZXOS menus) or as **Sinclair** keys (the number keys). Most games want **Kempston**. To
change it: press Space while the firmware boots, select the machine, edit its settings (press E,
the joysticks are on the second page) and set **Right Joy** (port 2) or **Left Joy** (port 1) to
**Kempston 1**, then save. The ZX Next stores it in the image. One fire button is supported.

Options menu
------------

Press **Help** for the options menu: HDMI mode (720p, 576p, 640x480, 720x480, 800x600), VGA
mode (standard or 15 kHz retro), flip joystick ports, HDMI CRT emulation, audio improvements,
Reset ZX Next and the help pages. The settings are not saved: the ZX Next owns the SD card while it runs.

Known issues
------------

* Only tested on R6. R4/R5 are untested.
* Not tested yet: a real ZX Next SD card (direct mode), VGA output, F13, the NMI keys (F9/F11),
  the **Reset ZX Next** menu item.
* Real ZX Next SD cards must be FAT32; FAT16 cards are not supported.
* No mouse: the ZX Next's (PS/2) mouse is not connected to the MEGA65's mouse.
* The boot screen of the ZX Next firmware says "MiSTer Next" (the firmware chooses it by the
  machine ID the core reports).
* +3 disk images (.DSK) have not been tested yet.

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
