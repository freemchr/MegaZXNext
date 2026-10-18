# MegaZXNext — Project Guide for Coding Agents

This is the cold-start brief for coding agents working on **MegaZXNext**, the port of the
ZX Next MiSTer core (ZXNext_MiSTer) to the **MEGA65**, built on the **MiSTer2MEGA65 (M2M)**
framework. **Naming:** the System/Next licence forbids calling systems built from the ZX Next
VHDL "ZX Spectrum Next". Our core is "MegaZXNext" / "a ZX Next core for the MEGA65"; never name
it "ZX Spectrum Next" in screens, docs or releases (describing the original machine is fine). Read it first: it covers what this repo is, how it is laid out, where it deviates
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
  (`TBBLUE.FW`, `TBBLUE.TBU`), ROMs and NextZXOS **from its own SD card**, which on the MEGA65
  (as on MiSTer) is an **image file**: `/zxnext/boot.vhd` or `/zxnext/boot.img` on the MEGA65's
  SD card. Core version 3.02.00, which matches System/Next 24.11 (the latest distribution).
- **MiSTer core:** [MiSTer-devel/ZXNext_MISTer](https://github.com/MiSTer-devel/ZXNext_MISTer),
  pinned as the git submodule `CORE/ZXNext_MiSTer` (commit `7daebd1`). Original ZX Next RTL
  by Alvin Albrecht, Fabio Belavenuto, Victor Trucco et al.; MiSTer port by Sorgelig.
- **MEGA65 port:** Chris Freeman, 2026, GPL v3. Repo: https://github.com/freemchr/MegaZXNext
- **Framework:** M2M **V2.0.1** (`M2M/` tree identical to upstream tag `V2.0.1` except the
  four top files listed in §4), QNICE submodule at `2eb27dd` (V2.0.1's pin).
- **Status:** R3, R4, R5 and R6 synthesize with Vivado 2026.1 and meet timing (R3: 1 MB, §1). **V1.0 is released**
  (R6; R4/R5 builds included, untested). On R6: NextZXOS boots from `/zxnext/boot.img`; its menus, 48K BASIC, the Browser, .TAP loading and a Kempston joystick
  work. The V0.2 grey screen after resets was reported gone with the V0.3 build (SDRAM read hold
  timing fix, §3.2). Everything else is unverified until someone runs it on a MEGA65. The maintainer can only test
  on R6; R4/R5 are untested and need outside testers before they are called working.

### Target boards

The ZX Next's 2 MB of RAM live in the MEGA65's **SDRAM**, which only exists on **R4, R5, R6**.
The **R3 / R3A** has no SDRAM: there the ZX Next gets **1 MB of block RAM** (`bram_zxn.vhd`), the
memory of an unexpanded ZX Next (NextZXOS reports 768K). `main.vhd`'s generic `G_RAM_BRAM`
(set by `mega65.vhd` from `G_BOARD = "MEGA65_R3"`) chooses. The R3 build meets timing but has
**not run on an R3** yet (the maintainer has no R3); the 1 MB machine itself was tested on an R6
(upper 1 MB of the SDRAM hidden: NextZXOS boots, `.MEM` 768K, games run). 1 MB of block RAM uses
256 of the 365 RAMB36: the R3 build is at 316.

---

## 2. Repository layout

```
/
├── AGENTS.md  CLAUDE.md    this guide (CLAUDE.md imports it)
├── README.md               user documentation: installation, keys, known issues
├── AUTHORS                 credits for everything the core uses
├── VERSIONS.md             this core's changelog (M2M's own is upstream)
├── M2M/                    the MiSTer2MEGA65 framework, V2.0.1. Read-only EXCEPT the
│                           four board tops listed in §4. M2M/QNICE = QNICE submodule.
├── CORE/
│   ├── ZXNext_MiSTer/      ← submodule, UNMODIFIED. All RTL is compiled from here (library "zxnext")
│   │                         except the files that CORE/vhdl/zxnext/ replaces.
│   ├── vhdl/
│   │   ├── mega65.vhd      entity MEGA65_Core: framework↔core contract + SD slot mux + menu decode
│   │   ├── main.vhd        core clock domain: zxnext_top_m65 + sdram_zxn + rtc + audio/video glue
│   │   ├── clk.vhd         MMCM: 28 / 28∠180° / 14 / 7 / 112 MHz
│   │   ├── globals.vhd     CORE_CLK_SPEED = 28 MHz, VGA_DX/DY = 720×576, no vdrives, no ROMs
│   │   ├── config.vhd      OSM menu (30 lines), welcome screen, 2 help pages
│   │   ├── keyboard.vhd    MEGA65 keyboard → ZX Next 8×7 membrane matrix
│   │   ├── sdram_zxn.vhd   SDRAM controller (VHDL translation of MiSTer rtl/mister/sdram.sv)
│   │   ├── bram_zxn.vhd    R3: 1 MB of ZX Next RAM in block RAM (no SDRAM on the R3)
│   │   ├── sd_image.vhd    the ZX Next's SD card = image file on the MEGA65 card (sector engine)
│   │   ├── sd_card_zxn.vhd virtual SPI SD card (VHDL translation of MiSTer sys/sd_card.sv)
│   │   ├── zxn_dc_blocker.vhd  audio DC blocker
│   │   └── zxnext/         replacements for MiSTer files, compiled into library "zxnext":
│   │       ├── zxnext_top_m65.vhd  derived from rtl/mister/zxnext_top.vhd (MEGA65 top of the ZX Next)
│   │       ├── bram_xilinx.vhd     replaces rtl/mister/bram.vhd (Altera altsyncram/altdpram → inferred RAM)
│   │       └── t80n.vhd            patched copy of rtl/cpu/t80n.vhd (vector-length fix Vivado needs)
│   ├── m2m-rom/            QNICE Shell ROM (m2m-rom.asm: PREP_START mounts the SD card image)
│   ├── sim/                GHDL testbenches: sdram_zxn (+ MJoergen's SDRAM model, MIT), sd_image
│   ├── CORE.xdc            core clocks, CPU BUFGMUX clocks, multicycles, SD pins (all boards)
│   ├── CORE-SDRAM.xdc      SDRAM multicycles, IOB packing, I/O timing (R4/R5/R6 .xpr only)
│   └── CORE-R{3,4,5,6}.xpr Vivado 2026.1 projects (same sources, different top/XDC/G_BOARD)
└── doc/
    ├── m2m/                M2M conventions; exceptions.md = how to re-apply our changes on updates
    ├── m2m-v2.1.0-upgrade.md   plan for moving M2M/ to V2.1.0
    ├── porting-guide-audit.md  audit against the M2M porting guide: open gaps
    └── temp/               M2M framework scratch notes, NOT about this core
```

---

## 3. Architecture

```
M2M/vhdl/top_mega65-rX.vhd             (PATCHED: R4/R5/R6 SDRAM to CORE; R3-R6 SD outputs via CORE)
├── i_framework : framework.vhd        stock M2M; QNICE has both SD slots until the image is mounted
└── CORE : MEGA65_Core (CORE/vhdl/mega65.vhd)
      ├── clk_gen : clk.vhd            MMCM 100 MHz → 700 MHz VCO → 112 / 28 / 28∠180 / 14 / 7 MHz
      ├── C_DEV_ZXN_IMG registers      image position from QNICE (cdc_stable → main_clk)
      ├── SD slot mux                  slot with the image: core; otherwise the framework
      ├── i_main : main.vhd            28 MHz domain
      │     ├── i_zxnext_top : zxnext_top_m65 (library zxnext) → the MiSTer ZX Next RTL
      │     ├── i_sd_image : sd_image  SD0 = virtual card (sd_card_zxn) served from the image
      │     ├── gen_sdram.i_sdram : sdram_zxn  112 MHz, 2 MB, ports A (CPU/DMA) and B (Layer 2)
      │     │   (R3: gen_bram.i_bram : bram_zxn, 28 MHz, 1 MB)
      │     ├── rtc (MiSTer)           DS1307 emulation fed by M2M's main_rtc_i
      │     ├── keyboard.vhd           membrane matrix
      │     └── zxn_dc_blocker         audio
      └── menu decode                  qnice_* AV-mode outputs from C_MENU_* bits
```

### 3.1 Clocks (`CORE/vhdl/clk.vhd`, `CORE/CORE.xdc`)

- One `MMCME2_ADV`: VCO = 100 MHz / 5 × 35 = 700 MHz. Outputs: CLKOUT0 = **112 MHz** SDRAM
  (fractional 6.25), CLKOUT1 = **28 MHz** main, CLKOUT2 = 28 MHz at 180°, CLKOUT3 = 14 MHz,
  CLKOUT4 = 7 MHz. All are phase aligned; `sdram_zxn` relies on 112 = 4 × 28 being phase aligned.
- A `PLLE2_BASE` (`i_pll_sdram`) makes `sdram_out_clk`: the 112 MHz clock, 56.25° (1.40 ns) late.
  It only clocks the ODDR of the SDRAM clock pin (§3.2). The MMCM can't: only CLKOUT0 is
  fractional.
- `CORE_CLK_SPEED` in `globals.vhd` = 28_000_000 and must match CLKOUT1.
- **CPU clock:** the ZX Next derives a register-driven CPU clock (`CLK_i0`, 3.5/7/14 MHz) and
  switches to 28 MHz via a **`BUFGMUX_CTRL`** (`zxnext_top_m65.vhd`; MiSTer used a fabric clock
  mux). `CORE.xdc` declares `cpu_clk_i0`, `cpu_clk_div`, `cpu_clk_28` as generated clocks, with
  `cpu_clk_div`/`cpu_clk_28` physically exclusive. Multicycle paths mirror MiSTer's `ZXNext.sdc`.
- **CPU speed changes:** the ZX Next sizes a memory cycle by its new speed at once
  (`memcycle_count_max`, the 28 MHz wait state), but the cycle that straddles the switch began at
  the old speed. MiSTer's mux (and ours at first) could end that opcode fetch before its memory
  request went out: on R6 NextZXOS lost an `INC HL` after its `OUT` to nextreg 0x07, the ULA clip
  window got garbage, 48K BASIC and the Browser showed a black screen. `zxnext_top_m65.vhd` therefore
  switches the BUFGMUX from `zxn_cpu_speed` (not the delayed `zxn_cpu_speed2`) and keeps `CLK_i0`
  from rising for 15 CLK_28 cycles after a speed change. `make speed` in `CORE/sim` tests it (48
  speed drops at different phases); run it after touching the CPU clock.
  **These XDC lines name hierarchical cells (`CORE/i_main/i_zxnext_top/...`, `CORE/i_main/gen_sdram.i_sdram/*` in `CORE-SDRAM.xdc`);
  renaming an instance silently drops the constraint.** Check the Vivado critical warnings after
  any rename.
- The video clock handed to M2M is the 28 MHz main clock: the pixel rate is 14 MHz, so
  `video_ce_o` is a 14 MHz enable. VGA_DX/DY = 720×576 is the scandoubled size.
- `hr_high_i`/`hr_low_i` (flicker-free HDMI) are not used: the core clock is fixed.

### 3.2 Memory (`CORE/vhdl/sdram_zxn.vhd`; R3: `bram_zxn.vhd`)

- **R3 / R3A:** `bram_zxn` is 1 MB of block RAM clocked by CLK_28, which is what the ZX Next was
  designed for (an SRAM, "transactions complete after one cycle"): port A writes or reads on the
  rising edge where `ram_a_req` = '1' and holds the read data; no wait states. Port B reads every
  cycle (Layer 2 latches 4 cycles after it changes the address). Above 1 MB reads 0xFF and writes
  are ignored: a mirror would pass NextZXOS's RAM test and corrupt memory later. `make speed_bram`
  runs the CPU speed test against it (passes up to 34 ns of data delay; real paths have ~2 ns slack
  at 17.9 ns). The rest of this section is about the SDRAM (R4/R5/R6).
- The 2 MB of ZX Next RAM live in the **SDRAM** (IS42S16320F-6BL). The core does **not** use
  HyperRAM (`C_HMAP_M2M` only). HyperRAM is still used by M2M for the HDMI scaler.
- Read the file header first. Key points: 112 MHz, CL3, tRCD 3, an ACTIVE every 8 cycles,
  IOB-registered outputs and DQ input, SDRAM clock = inverted `sdram_out_clk` via ODDR
  (MJoergen's MEGA65 I/O scheme; he runs it at 166 MHz). Port A (CPU/DMA) has a wait signal.
- **SDRAM I/O timing is constrained** in `CORE-SDRAM.xdc` (datasheet tAC/tOH/tIS/tIH, read data
  sampled CL+1 cycles after the READ). With the plain inverted controller clock (V0.2) the read
  hold slack was **-0.9 ns**: at 112 MHz the sample sat just after the data valid window. The
  1.4 ns of `sdram_out_clk` centre it. After a build, check the `sdram_pin_clk` paths; if you
  change the clock frequency, CAS latency or capture cycle, re-tune `CLKOUT0_PHASE` of the PLL. Port B (Layer 2
  fetch) has **no wait**: the controller learns the Layer 2 request phase and keeps the two
  cycles before it free. CPU writes invalidate a matching Port B cache line.
- **Port A is a 56 MHz interface:** it is evaluated, and `ram_a_wait`/`ram_a_do` change, only on
  the 112 MHz edges that coincide with an edge of CLK_28 (`clk_28_i` is the phase reference).
  The inputs come from the ZX Next's combinational memory decode, launched by either CLK_28/CPU
  edge, and are garbage for up to 2 cycles in between. This is what the CPU↔`sdram_clk`
  multicycles in `CORE.xdc` assume; keep the two in sync.
- **Port A must accept a request while it is busy.** At 28 MHz the Z80N cannot be stalled by its
  own write (WR goes low in T2, when WAIT is sampled), so the next request (e.g. the opcode fetch
  after a `CALL`'s push) can arrive before the write is served. `sdram_zxn` queues one such
  request (`a_queued`, `a_q_*`) and keeps `ram_a_wait` high until it is served. Without it the read
  returned the written byte and TBBLUE.FW crashed (found on R6 hardware). Test 9 in
  `tb_sdram_zxn.vhd` covers it.
- DQ is split into `dq_out`/`dq_oe_n`/`dq_in`. The tri-states are in the patched board tops.
- **Simulate before touching it:** `cd CORE/sim && make` (GHDL, `--std=08`). The testbench uses
  MJoergen's SDRAM model and checks with `--assert-level=error`.

### 3.3 SD card image (`sd_image.vhd`, `sd_card_zxn.vhd`, `m2m-rom.asm`, `mega65.vhd`)

- The ZX Next talks SPI to its SD card. As on MiSTer, that card is an **image file**: SD0 is a
  virtual SD card (`sd_card_zxn.vhd`, a VHDL translation of MiSTer's `sys/sd_card.sv`) whose
  sectors are served from `/zxnext/boot.vhd` (or `/zxnext/boot.img`) on the MEGA65's SD card.
  SD1 has no card. A MiSTer `boot.vhd` (fixed VHD = raw image + 512-byte footer) works as is.
- **Startup:** the Shell's `PREP_START` calls `ZXN_MOUNT` (`CORE/m2m-rom/zxn_mount.asm`): it mounts
  the card, opens the image and walks its FAT chain. Every piece of the file (**extent**: first
  virtual sector, first physical sector) goes into the core's 512-entry extent table; then size,
  extent count and slot go to device `C_DEV_ZXN_IMG` (`globals.vhd`; register map in
  `mega65.vhd`), "mounted" last. Fragmented files are fine (up to 512 pieces). Errors (no card, no
  image, more than 512 pieces, broken chain) are fatal Shell errors with instructions. The serial
  log shows `ZX Next: image at sector 0x…, sectors 0x…, extents 0x…, slot …`.
- **QNICE assembly:** `ADD`/`ADDC` (and `SUB`/`SUBC`) pairs must be adjacent: any `ADD` in between,
  even one that only forms a pointer, changes the carry flag (this bug once put the image 32 MB
  too early). Test: `cd CORE/m2m-rom/test && ./run_test.sh` (QNICE emulator, FAT32 test images:
  carry case, 3 extents, >512 extents, boot.vhd, no image).
- **Ownership:** until "mounted", QNICE has both slots and the ZX Next is held in a hard reset
  (`main.vhd`). From then on the core drives the slot that holds the image (mux in `mega65.vhd`,
  framework outputs passed through the CORE by the patched board tops) and **QNICE must not touch
  the SD card any more**: no file browser, no vdrives, no settings file (`SAVE_SETTINGS = false`).
- **Direct mode (real ZX Next SD card):** if neither image exists but `/TBBLUE.FW` does,
  `ZXN_MOUNT` sets register 8 of `C_DEV_ZXN_IMG` (direct) instead of an extent table. `main.vhd`
  then disables `sd_image` and wires the ZX Next's SPI (`sd_cs0_n`, SCK, MOSI, MISO) straight to
  the slot, as on a real Next (SCK = CPU clock / 2, up to 14 MHz). FAT32 only (QNICE has to read
  the card first). QNICE test case 5 covers the detection; not yet tested on hardware.
- **Which slot:** M2M's `sdmux` uses the back slot if a card is in it, otherwise the bottom
  tray; `ZXN_MOUNT` reads `M2M$CSR_SD_ACTIVE` and the core then drives that slot.
- **Sector engine** (`sd_image.vhd`): virtual sector N is found in the extent table (linear
  search, a few µs), then read/written
  with M2M's `sd_controller` (`sd_spi.vhd`, the Shell's own SD controller) at 28 MHz (14 MHz SPI).
  Sectors beyond the image read as zeros and are not written. Three tries per sector, then the
  sector is acknowledged anyway and counted (register 6 of `C_DEV_ZXN_IMG`).
- **CPU wait:** the Z80N (and DMA) waits while a write is stored (as MiSTer), and while a
  prefetched sector that nobody wants any more is still in flight. The latter is not in MiSTer: it
  closes a race in `sd_card.sv` (CMD12 during a CMD18 prefetch, then CMD17/24) that corrupts
  writes when the card is slow. `tb_sd_image.vhd` reproduces it.
- **Simulate before touching it:** `cd CORE/sim && make sd`. It uses the ZX Next's real
  `spi_master.vhd` and a behavioural SDHC card (CRC16, read latency, injected CRC errors).
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
  (23), HDMI CRT emulation (24), Audio improvements (25), Reset ZX Next (26), About & Help (28),
  Close (30). Main menu shows 13 lines with `OPTM_DY = 13`.
- **Reset ZX Next** is an action, not a setting: `main.vhd` makes a soft reset on the rising edge
  of its bit, and the Shell's `OSM_SEL_POST` (`m2m-rom.asm`) unselects the item again. It can't
  use the CSR reset: the board tops OR that into `main_reset_m2m`, i.e. the ZX Next hard reset.
- There is no HDMI Zoom-in item: M2M's `crop.vhd` is hard-coded for the C64 picture (320x200 behind 33/35 pixel borders), so `qnice_zoom_crop_o` is
  tied to '0'. A ZX Next zoom would need its own crop in the core.
- **Bit N of the OSM control vector = menu line N = `C_MENU_*` in `mega65.vhd`.**
  Inserting or deleting a line silently shifts every later index. Re-sync `C_MENU_*` and keep
  `OPTM_SIZE` = number of lines in `OPTM_ITEMS` = number of entries in `OPTM_GROUPS`.
- `cpu_speed_sw_i` on `main` is tied to `'0'`: there is no CPU speed menu item (use F13).

---

## 4. Deviations from upstream (keep this list complete)

**MiSTer core** (`CORE/ZXNext_MiSTer` is unmodified; replacements live in `CORE/vhdl/`):

| Upstream file | Replacement | Why |
| --- | --- | --- |
| `rtl/mister/zxnext_top.vhd` | `CORE/vhdl/zxnext/zxnext_top_m65.vhd` | No PS/2; membrane driven directly; BUFGMUX_CTRL CPU clock with a settle time after speed changes; real 180° clock |
| `rtl/mister/bram.vhd` | `CORE/vhdl/zxnext/bram_xilinx.vhd` | Altera `altsyncram`/`altdpram` → inferable VHDL (same entities/ports). `.mif` init not supported |
| `rtl/cpu/t80n.vhd` | `CORE/vhdl/zxnext/t80n.vhd` | 9-bit vs 4-bit mask length mismatch (`x"7"` → `"000000111"`) |
| `rtl/mister/sdram.sv` | `CORE/vhdl/sdram_zxn.vhd` | VHDL translation for the MEGA65 SDRAM at 112 MHz (see §3.2) |
| `sys/sd_card.sv` | `CORE/vhdl/sd_card_zxn.vhd` | VHDL translation (SDHC, 8-bit buffer, `zxnext.dpram`), plus `idle_o` for the CPU wait (see §3.3) |

When bumping the submodule, diff these five upstream files against the version the replacement
was made from and carry over any changes. The `.xpr` files list each MiSTer RTL file
explicitly (library `zxnext`), so files that upstream adds or renames must be added by hand
to **all four** `.xpr`s.

**M2M framework** (V2.0.1): only `M2M/vhdl/top_mega65-r3.vhd`, `-r4.vhd`, `-r5.vhd`, `-r6.vhd` are
changed. R4-R6 (a) remove the SDRAM tie-offs, adds the DQ tri-state generate and routes all `sdram_*`
pins to the CORE; all four (b) route the framework's SD outputs (`sd_reset/clk/mosi`, `sd2_*`) through
the CORE's `fw_sd*_i` ports, which drives the pins (`sd_*`/`sd2_*` outputs); MISO and card detect
go from the pins to the framework directly, MISO also to the CORE. Re-apply both when updating M2M. See
`doc/m2m-v2.1.0-upgrade.md`.

**QNICE:** none.

---

## 5. Build, simulate, flash

```bash
git submodule update --init                 # CORE/ZXNext_MiSTer and M2M/QNICE

# QNICE toolchain (one-time) and Shell ROM. Vivado also runs CORE/m2m-rom/synth_pre.tcl at synthesis.
( cd M2M/QNICE/tools && ./make-toolchain.sh )
( cd CORE/m2m-rom && ./make_rom.sh )

# Simulations (GHDL): SDRAM controller and SD card image
( cd CORE/sim && make )                     # or: make sdram / sd / speed / speed_bram (R3 RAM); make clean

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

**Test on hardware with:** the normal MEGA65 SD card (FAT32) with an image of a ZX Next SD card
(e.g. MiSTer's `boot.vhd`, or a FAT32 image holding System/Next 24.11) copied to
`/zxnext/boot.vhd` or `/zxnext/boot.img` (it may be fragmented, up to 512 pieces).

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
- The CPU↔`sdram_clk` multicycles in `CORE-SDRAM.xdc` (2 cycles each way, from MiSTer's `ZXNext.sdc`)
  and the `main_clk`→Port A multicycle are only correct because Port A samples and updates on
  even edges only (§3.2). Anything in `sdram_zxn` that reads `ram_a_*_i` or drives `ram_a_*_o`
  on another edge breaks them silently: STA still passes. The testbench catches it (garbage
  inputs, odd-edge output check). Renaming the Port A registers (or `last_data`, whose clock
  enable sees `ram_a_req_i` only through the even-edge queue branch) drops the `main_clk`
  multicycle (it filters by cell name). Don't add more multicycles without proving the capture
  register really waits that long.
- `C_MENU_*` ↔ menu line coupling (§3.5). The main menu uses all 13 lines of `OPTM_DY`; on
  M2M V2.1.0 an oversized menu is a fatal Shell error.
- QNICE must not use the SD card after `PREP_START` (§3.3): the core drives it. Anything in the
  Shell that needs files after startup (file browser, settings, vdrives) would collide with it.
- The XDC uses hierarchical names; instance renames drop constraints silently.
- `doc/temp/*` are upstream M2M scratch notes, not documentation of this core.
- Vivado 2026.1 has mis-synthesized VHDL procedures that write process variables implicitly (seen
  in another port). Pass variables as explicit `inout` parameters; if hardware and simulation
  disagree, suspect synthesis.

---

## 8. Open items

The audit against the Porting Guide is recorded in `doc/porting-guide-audit.md`. V1.0 (R6
tested, R4/R5 untested) is released. Known issues are listed in `README.md` and `VERSIONS.md`.
If the grey screen comes back: CPU trace probe triggered by the DivMMC interrupt handler saving
an SP of 0x26xx to 0x25B8 (i.e. re-entering itself). Still to do: test VGA, F13,
NMI keys, .DSK, saving settings, Reset ZX Next; mouse support; R4/R5 testers.
Requested by the maintainer: a "MEGA65 Next" boot screen with the logo in
`doc/assets/mega65-logo.png` instead of the firmware's "MiSTer Next" (the firmware picks that text
by the machine ID 0xDA; not in our code). Keep the version in `config.vhd` (welcome screen,
HELP_1, `CORENAME`) and `VERSIONS.md` in sync.

## 9. Lessons from other M2M ports

`/home/freemchr/github/m2m-porting-lessons/README.md`
(https://github.com/freemchr/m2m-porting-lessons) collects what earlier ports (MegaST) learnt the
hard way: memory latency budgets, M2M V2.0.1 bugs, resets, Vivado and QNICE pitfalls, MEGA65
hardware facts, verification and release practice. Read it before porting work or when debugging
framework, Vivado or hardware problems. Where it applies here:

- OSM size: this core's OSM is 720x576 with a 16x16 font, i.e. 45x36 characters. Inside the frame
  a help line can be at most 43 characters (MegaST's 640x400 limits do not apply).
- Resets: `main_reset_m2m_i`/`main_reset_core_i` also carry the QNICE CSR reset (lessons §3.4).
- Board tops: R3 differs from R4-R6 (no SDRAM, other controllers); its RAM is block RAM (§1, §3.2).
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
