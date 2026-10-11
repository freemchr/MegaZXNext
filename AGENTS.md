# MegaZXNext — Project Guide for Coding Agents

This is the cold-start brief for coding agents working on **MegaZXNext**, the port of the
**ZX Spectrum Next** MiSTer core to the **MEGA65**, built on the **MiSTer2MEGA65 (M2M)**
framework. Read it first: it covers what this repo is, how it is laid out, where it deviates
from the stock M2M template, how to build and simulate it, and the gotchas. Spend your context
on the task, not on rediscovering the layout.

> This file describes **this core**, not the M2M framework. For framework internals use the
> upstream guide: https://github.com/sy2002/MiSTer2MEGA65/blob/develop/AGENTS.md and
> [The Ultimate MiSTer2MEGA65 Porting Guide](https://github.com/sy2002/MiSTer2MEGA65/wiki/The-Ultimate-MiSTer2MEGA65-Porting-Guide).
> Where this file and the source disagree, trust the source and fix this file.

---

## 1. What is this project?

- **ZX Spectrum Next**: an FPGA-based, enhanced ZX Spectrum (Z80N CPU at 3.5/7/14/28 MHz,
  Layer 2 / tilemap / sprites, AY×3, DivMMC, Multiface, 2 MB RAM). It boots its firmware
  (`TBBLUE.FW`, `TBBLUE.TBU`), ROMs and NextZXOS **from its own SD card**.
- **MiSTer core:** [MiSTer-devel/ZXNext_MISTer](https://github.com/MiSTer-devel/ZXNext_MISTer),
  pinned as the git submodule `CORE/ZXNext_MiSTer` (commit `7daebd1`). Original ZX Next RTL
  by Alvin Albrecht, Fabio Belavenuto, Victor Trucco et al.; MiSTer port by Sorgelig.
- **MEGA65 port:** Chris Freeman, 2026, GPL v3. Repo: https://github.com/freemchr/MegaZXNext
- **Framework:** M2M **V2.0.1** (`M2M/` tree identical to upstream tag `V2.0.1` except the
  three top files listed in §4), QNICE submodule at `2eb27dd` (V2.0.1's pin).
- **Status:** R6 synthesizes with Vivado 2026.1 and meets timing. **Not yet tested on
  hardware.** Treat every behavioral claim as unverified until someone runs it on a MEGA65.

### Target boards

The ZX Next's 2 MB of RAM live in the MEGA65's **SDRAM**, which only exists on **R4, R5, R6**.
`CORE/CORE-R3.xpr` exists, but the R3 top file is stock M2M and R3 has no SDRAM, so the core
would have no RAM and no SD card. An `assert` in `mega65.vhd` makes the R3 build fail on purpose:
**R3 is not a supported target**. The help screen says "Requires a
MEGA65 R4, R5 or R6".

---

## 2. Repository layout

```
/
├── AGENTS.md  CLAUDE.md    this guide (CLAUDE.md imports it)
├── README.md               ⚠ still the stock M2M README (see §8)
├── AUTHORS                 ⚠ still the M2M credit template (see §8)
├── VERSIONS.md             ⚠ still the M2M framework changelog (see §8)
├── M2M/                    the MiSTer2MEGA65 framework, V2.0.1. Read-only EXCEPT the
│                           three board tops listed in §4. M2M/QNICE = QNICE submodule.
├── CORE/
│   ├── ZXNext_MiSTer/      ← submodule, UNMODIFIED. All RTL is compiled from here (library "zxnext")
│   │                         except the files that CORE/vhdl/zxnext/ replaces.
│   ├── vhdl/
│   │   ├── mega65.vhd      entity MEGA65_Core: framework↔core contract + SD slot mux + menu decode
│   │   ├── main.vhd        core clock domain: zxnext_top_m65 + sdram_zxn + rtc + audio/video glue
│   │   ├── clk.vhd         MMCM: 28 / 28∠180° / 14 / 7 / 112 MHz
│   │   ├── globals.vhd     CORE_CLK_SPEED = 28 MHz, VGA_DX/DY = 720×576, no vdrives, no ROMs
│   │   ├── config.vhd      OSM menu (31 lines), welcome screen, 2 help pages
│   │   ├── keyboard.vhd    MEGA65 keyboard → ZX Next 8×7 membrane matrix
│   │   ├── sdram_zxn.vhd   SDRAM controller (VHDL translation of MiSTer rtl/mister/sdram.sv)
│   │   ├── zxn_dc_blocker.vhd  audio DC blocker
│   │   └── zxnext/         replacements for MiSTer files, compiled into library "zxnext":
│   │       ├── zxnext_top_m65.vhd  derived from rtl/mister/zxnext_top.vhd (MEGA65 top of the ZX Next)
│   │       ├── bram_xilinx.vhd     replaces rtl/mister/bram.vhd (Altera altsyncram/altdpram → inferred RAM)
│   │       └── t80n.vhd            patched copy of rtl/cpu/t80n.vhd (vector-length fix Vivado needs)
│   ├── m2m-rom/            QNICE Shell ROM (m2m-rom.asm is the unmodified template)
│   ├── sim/                GHDL testbench for sdram_zxn (+ MJoergen's SDRAM model, MIT)
│   ├── CORE.xdc            core clocks, CPU BUFGMUX clocks, multicycles, SDRAM IOB packing
│   └── CORE-R{3,4,5,6}.xpr Vivado 2026.1 projects (same sources, different top/XDC/G_BOARD)
└── doc/
    ├── m2m/                M2M conventions; ⚠ exceptions.md is still the template (see §8)
    ├── m2m-v2.1.0-upgrade.md   plan for moving M2M/ to V2.1.0
    ├── porting-guide-audit.md  audit against the M2M porting guide: open gaps
    └── temp/               M2M framework scratch notes, NOT about this core
```

---

## 3. Architecture

```
M2M/vhdl/top_mega65-rX.vhd             (PATCHED on R4/R5/R6: SD + SDRAM routed to CORE)
├── i_framework : framework.vhd        stock M2M; QNICE sees two EMPTY SD slots
└── CORE : MEGA65_Core (CORE/vhdl/mega65.vhd)
      ├── clk_gen : clk.vhd            MMCM 100 MHz → 700 MHz VCO → 112 / 28 / 28∠180 / 14 / 7 MHz
      ├── sd_select_proc               maps ZX Next SD0/SD1 onto the back slot / bottom tray
      ├── i_main : main.vhd            28 MHz domain
      │     ├── i_zxnext_top : zxnext_top_m65 (library zxnext) → the MiSTer ZX Next RTL
      │     ├── i_sdram : sdram_zxn    112 MHz, 2 MB, ports A (CPU/DMA) and B (Layer 2)
      │     ├── rtc (MiSTer)           DS1307 emulation fed by M2M's main_rtc_i
      │     ├── keyboard.vhd           membrane matrix
      │     └── zxn_dc_blocker         audio
      └── menu decode                  qnice_* AV-mode outputs from C_MENU_* bits
```

### 3.1 Clocks (`CORE/vhdl/clk.vhd`, `CORE/CORE.xdc`)

- One `MMCME2_ADV`: VCO = 100 MHz / 5 × 35 = 700 MHz. Outputs: CLKOUT0 = **112 MHz** SDRAM
  (fractional 6.25), CLKOUT1 = **28 MHz** main, CLKOUT2 = 28 MHz at 180°, CLKOUT3 = 14 MHz,
  CLKOUT4 = 7 MHz. All are phase aligned; `sdram_zxn` relies on 112 = 4 × 28 being phase aligned.
- `CORE_CLK_SPEED` in `globals.vhd` = 28_000_000 and must match CLKOUT1.
- **CPU clock:** the ZX Next derives a register-driven CPU clock (`CLK_i0`, 3.5/7/14 MHz) and
  switches to 28 MHz via a **`BUFGMUX_CTRL`** (`zxnext_top_m65.vhd`; MiSTer used a fabric clock
  mux). `CORE.xdc` declares `cpu_clk_i0`, `cpu_clk_div`, `cpu_clk_28` as generated clocks, with
  `cpu_clk_div`/`cpu_clk_28` physically exclusive. Multicycle paths mirror MiSTer's `ZXNext.sdc`.
  **These XDC lines name hierarchical cells (`CORE/i_main/i_zxnext_top/...`, `CORE/i_main/i_sdram/*`);
  renaming an instance silently drops the constraint.** Check the Vivado critical warnings after
  any rename.
- The video clock handed to M2M is the 28 MHz main clock: the pixel rate is 14 MHz, so
  `video_ce_o` is a 14 MHz enable. VGA_DX/DY = 720×576 is the scandoubled size.
- `hr_high_i`/`hr_low_i` (flicker-free HDMI) are not used: the core clock is fixed.

### 3.2 Memory (`CORE/vhdl/sdram_zxn.vhd`)

- The 2 MB of ZX Next RAM live in the **SDRAM** (IS42S16320F-6BL). The core does **not** use
  HyperRAM (`C_HMAP_M2M` only). HyperRAM is still used by M2M for the HDMI scaler.
- Read the file header first. Key points: 112 MHz, CL3, tRCD 3, an ACTIVE every 8 cycles,
  IOB-registered outputs and DQ input, SDRAM clock = inverted controller clock via ODDR
  (MJoergen's proven MEGA65 I/O scheme). Port A (CPU/DMA) has a wait signal. Port B (Layer 2
  fetch) has **no wait**: the controller learns the Layer 2 request phase and keeps the two
  cycles before it free. CPU writes invalidate a matching Port B cache line.
- **Port A is a 56 MHz interface:** it is evaluated, and `ram_a_wait`/`ram_a_do` change, only on
  the 112 MHz edges that coincide with an edge of CLK_28 (`clk_28_i` is the phase reference).
  The inputs come from the ZX Next's combinational memory decode, launched by either CLK_28/CPU
  edge, and are garbage for up to 2 cycles in between. This is what the CPU↔`sdram_clk`
  multicycles in `CORE.xdc` assume; keep the two in sync.
- DQ is split into `dq_out`/`dq_oe_n`/`dq_in`. The tri-states are in the patched board tops.
- **Simulate before touching it:** `cd CORE/sim && make` (GHDL, `--std=08`). The testbench uses
  MJoergen's SDRAM model and checks with `--assert-level=error`.

### 3.3 SD cards (`mega65.vhd` `sd_select_proc`)

- The ZX Next talks SPI to its SD cards itself, with two chip selects (SD0 = boot card, SD1).
  **Both MEGA65 SD slots are owned by the core**, not by QNICE. Consequences:
  - The M2M Shell has **no SD card**: no file browser, no ROM loading, no settings file
    (`SAVE_SETTINGS = false`, `C_VDNUM = 0`, `C_CRTROMS_*_NUM = 0`). Do not enable any of these
    without first giving QNICE an SD path.
  - SD0 = back slot if a card is there at reset, otherwise the bottom tray; SD1 = the other.
    The choice is latched during reset (card detect is synchronized in `main_clk`).
- `CORE.xdc` sets the SD pins as false paths (SPI is slow and source-synchronous).

### 3.4 Keyboard, joysticks, RTC, LEDs

- `keyboard.vhd` header has the complete MEGA65 → ZX Next mapping table. Function keys:
  F3 = 50/60 Hz, F9 = Multiface NMI, F11 = DivMMC NMI, F13 = cycle CPU speed. Help = OSM.
- No PS/2 keyboard or mouse: the membrane matrix is driven directly; mouse inputs are idle.
- RTC: MiSTer's `rtc` (DS1307 over I²C) fed from `main_rtc_i`.
- Machine ID `0xDA` ("MiSTer": no flash, no bootstrap, no Pi), board issue 0 (`main.vhd`).
- Power LED green (blue during M2M reset); drive LED yellow = SD activity.
- `cart_en_o <= '1'` is the required R5/R6 joystick-port-2 workaround. Keep it.

### 3.5 OSM menu (`config.vhd` ↔ `mega65.vhd`)

- 31 lines (`OPTM_SIZE = 31`): HDMI submenu (lines 2–13), VGA submenu (14–21), Flip joysticks
  (23), HDMI CRT emulation (24), HDMI Zoom-in (25), Audio improvements (26), About & Help (28),
  Close (30). Main menu shows 13 lines with `OPTM_DY = 13`.
- **Bit N of the OSM control vector = menu line N = `C_MENU_*` in `mega65.vhd:279-292`.**
  Inserting or deleting a line silently shifts every later index. Re-sync `C_MENU_*` and keep
  `OPTM_SIZE` = number of lines in `OPTM_ITEMS` = number of entries in `OPTM_GROUPS`.
- `cpu_speed_sw_i` on `main` is tied to `'0'`: there is no CPU speed menu item (use F13).

---

## 4. Deviations from upstream (keep this list complete)

**MiSTer core** (`CORE/ZXNext_MiSTer` is unmodified; replacements live in `CORE/vhdl/`):

| Upstream file | Replacement | Why |
| --- | --- | --- |
| `rtl/mister/zxnext_top.vhd` | `CORE/vhdl/zxnext/zxnext_top_m65.vhd` | No PS/2; membrane driven directly; BUFGMUX_CTRL CPU clock; real 180° clock |
| `rtl/mister/bram.vhd` | `CORE/vhdl/zxnext/bram_xilinx.vhd` | Altera `altsyncram`/`altdpram` → inferable VHDL (same entities/ports). `.mif` init not supported |
| `rtl/cpu/t80n.vhd` | `CORE/vhdl/zxnext/t80n.vhd` | 9-bit vs 4-bit mask length mismatch (`x"7"` → `"000000111"`) |
| `rtl/mister/sdram.sv` | `CORE/vhdl/sdram_zxn.vhd` | VHDL translation for the MEGA65 SDRAM at 112 MHz (see §3.2) |

When bumping the submodule, diff these four upstream files against the version the replacement
was made from and carry over any changes. The `.xpr` files list each MiSTer RTL file
explicitly (library `zxnext`), so files that upstream adds or renames must be added by hand
to **all four** `.xpr`s.

**M2M framework** (V2.0.1): only `M2M/vhdl/top_mega65-r4.vhd`, `-r5.vhd`, `-r6.vhd` are changed.
Each one (a) removes the SDRAM tie-offs, adds the DQ tri-state generate and routes all `sdram_*`
pins to the CORE, and (b) disconnects both SD slots from the framework (`open` / `'1'`) and
routes them to the CORE's new `sd_*`/`sd2_*` ports. Re-apply both when updating M2M. See
`doc/m2m-v2.1.0-upgrade.md`.

**QNICE:** none.

---

## 5. Build, simulate, flash

```bash
git submodule update --init                 # CORE/ZXNext_MiSTer and M2M/QNICE

# QNICE toolchain (one-time) and Shell ROM. Vivado also runs CORE/m2m-rom/synth_pre.tcl at synthesis.
( cd M2M/QNICE/tools && ./make-toolchain.sh )
( cd CORE/m2m-rom && ./make_rom.sh )

# SDRAM controller simulation (GHDL)
( cd CORE/sim && make )                     # make clean to reset

# Bitstream: open CORE/CORE-R6.xpr (or R4/R5) in Vivado 2026.1 →
#   Run Synthesis → Run Implementation → Generate Bitstream
#   → CORE/CORE-R6.runs/impl_1/mega65_r6.bit
# JTAG:   m65 -q CORE/CORE-R6.runs/impl_1/mega65_r6.bit   (mega65-tools)
# .cor:   bit2core / coretool (see the M2M wiki release page)
```

Vivado 2026.1 lives in `~/Xilinx/2026.1` (`source ~/Xilinx/2026.1/Vivado/settings64.sh`); it is
not on the PATH by default. On Ubuntu 26.04 Vivado needs `libncurses.so.5`, which the OS no longer
ships: point `LD_LIBRARY_PATH` at a private directory with a symlink
`libncurses.so.5 -> /usr/lib/x86_64-linux-gnu/libncursesw.so.6` instead of changing the system.

Batch build (headless, same `.xpr`):

```tcl
open_project CORE/CORE-R6.xpr
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
open_run impl_1
report_timing_summary -file timing_summary.rpt
check_timing -verbose -file check_timing.rpt
```

- Run long builds detached (`setsid nohup ...`). Other agent sessions on the same machine build
  other cores with Vivado; never `pkill`/`pgrep -f vivado` (it hits their builds, and theirs hit
  yours). Kill only by the PID you started.
- **Vivado rewrites the `.xpr` files** when it opens them (format, absolute paths). After a build,
  `git checkout -- CORE/*.xpr` unless you intended a file-list change.
- `runme.log` is appended across runs: read only from the last "Start of session".
- After every build check: WNS and WHS >= 0, no critical warnings, no block RAM demoted to LUTRAM
  (Synth 8-5835). Known and fine: `t80n.vhd` `RegsH`/`RegsL` implemented in registers (8-4767).
- If you can't run synthesis, say so; don't claim timing results.

**Test on hardware with:** a FAT32 SD card that holds a ZX Next distribution (`TBBLUE.FW`,
`TBBLUE.TBU`, `machines/`, `nextzxos/`, …) in the back slot or the bottom tray.

---

## 6. Conventions

- Follow the M2M conventions: `lower_snake_case`, `_i`/`_o`/`_n` suffixes, clock-domain
  prefixes (`qnice_*`, `main_*`, `hr_*`, `video_*`); **crossing a prefix boundary without a CDC
  is a bug**. 3-space VHDL indentation, aligned `:`/`=>`, as in the existing files.
- File headers: see `doc/m2m/example-file-headers.md`. Modified MiSTer files keep their
  original header with ours prepended (see `t80n.vhd`).
- "Avoid touching the original": wrap or replace MiSTer files from `CORE/vhdl/`, never edit
  the submodule. Record every replacement in §4 here and in `doc/m2m/exceptions.md`.
- QNICE assembly: no apostrophes in comments (the C preprocessor chokes on them).
- `M2M/` is read-only except the documented top-file patches.

---

## 7. Gotchas

- Changing a clock: edit `clk.vhd` **and** `CORE_CLK_SPEED`, and check `CORE.xdc` (the generated
  clock names/pins and the multicycles assume 112 = 4 × 28 MHz).
- `sdram_zxn` assumes its clock is exactly 4× and phase aligned with `CLK_28`; Layer 2 timing
  depends on that.
- The CPU↔`sdram_clk` multicycles in `CORE.xdc` (2 cycles each way, from MiSTer's `ZXNext.sdc`)
  and the `main_clk`→Port A multicycle are only correct because Port A samples and updates on
  even edges only (§3.2). Anything in `sdram_zxn` that reads `ram_a_*_i` or drives `ram_a_*_o`
  on another edge breaks them silently: STA still passes. The testbench catches it (garbage
  inputs, odd-edge output check). Renaming the Port A registers drops the `main_clk` multicycle
  (it filters by cell name). Don't add more multicycles without proving the capture register
  really waits that long.
- `C_MENU_*` ↔ menu line coupling (§3.5). The main menu already uses all 13 lines of
  `OPTM_DY`; on M2M V2.1.0 an oversized menu is a fatal Shell error.
- QNICE has no SD card (§3.3). Anything in the Shell that needs files will fail.
- The XDC uses hierarchical names; instance renames drop constraints silently.
- `doc/temp/*` are upstream M2M scratch notes, not documentation of this core.
- **HDMI "Zoom-in" uses M2M's `crop.vhd`, which is hard-coded for the C64 (320x200 picture
  behind 33/35 pixel borders).** On the ZX Next's 720-pixel raster it crops the wrong window.
  Either crop in the core or remove the menu item.
- Vivado 2026.1 has mis-synthesized VHDL procedures that write process variables implicitly (seen
  in another port). Pass variables as explicit `inout` parameters; if hardware and simulation
  disagree, suspect synthesis.

---

## 8. Open items

The audit against the Porting Guide is recorded in `doc/porting-guide-audit.md`. Highest
priority: the SDRAM I/O constraints (audit item 3), then hardware bring-up on R6. Release hygiene that is still on the template:
`README.md`, `AUTHORS`, `VERSIONS.md`, `doc/m2m/exceptions.md`, the `CORE/m2m-rom/m2m-rom.asm`
header, and "Version [WIP]" in the welcome screen.

## 9. Lessons from other M2M ports

`/home/freemchr/github/m2m-porting-lessons/README.md`
(https://github.com/freemchr/m2m-porting-lessons) collects what earlier ports (MegaST) learnt the
hard way: memory latency budgets, M2M V2.0.1 bugs, resets, Vivado and QNICE pitfalls, MEGA65
hardware facts, verification and release practice. Read it before porting work or when debugging
framework, Vivado or hardware problems. Where it applies here:

- OSM size: this core's OSM is 720x576 with a 16x16 font, i.e. 45x36 characters. Inside the frame
  a help line can be at most 43 characters (MegaST's 640x400 limits do not apply).
- Resets: `main_reset_m2m_i`/`main_reset_core_i` also carry the QNICE CSR reset (lessons §3.4).
- Board tops: R3 differs from R4-R6; the R3 build is blocked on purpose (§1).
- Release: no ROMs are shipped (the user supplies the ZX Next distribution on the SD card); no
  settings file is needed (`SAVE_SETTINGS = false`). Use `bit2core` from mega65-tools, not the 4 MB
  capped copy in M2M. Never call a board "working" before a tester with that board confirmed it.
- Hardware debugging: TE0790 JTAG under WSL (`usbipd attach --wsl`), BSCANE2 probes instead of ILA
  (free licence), load test bitstreams over JTAG.

## 10. Pointers

- M2M framework + agent guide: https://github.com/sy2002/MiSTer2MEGA65 (develop: `AGENTS.md`)
- Porting guide: https://github.com/sy2002/MiSTer2MEGA65/wiki/The-Ultimate-MiSTer2MEGA65-Porting-Guide
- Updating M2M: https://github.com/sy2002/MiSTer2MEGA65/wiki/Updating-M2M-in-an-existing-core
- Reference core: https://github.com/MJoergen/C64MEGA65
- MEGA65 SDRAM controller this one borrows its I/O scheme from: https://github.com/MJoergen/SDRAM
- ZX Next MiSTer core: https://github.com/MiSTer-devel/ZXNext_MISTer
- MEGA65 Discord (M2M channel)
