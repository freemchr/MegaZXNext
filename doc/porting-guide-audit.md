Audit against The Ultimate MiSTer2MEGA65 Porting Guide
======================================================

Date: 2026-10-11. Audited commit: `abaf2c3`. Guide: wiki revision as of that date (line numbers
below refer to `The-Ultimate-MiSTer2MEGA65-Porting-Guide.md`).

This is a source audit only. Nothing was synthesized or run on hardware. Items marked
**verified** were re-checked by hand against the source after the automated pass.

Gaps (most severe first)
------------------------

### A. Likely to break on hardware or in timing

**R6 build of `cd09f1c` (Vivado 2026.1, 2026-10-11):** all constraints met, WNS +0.124 ns (inside
`cpu_clk_28`, rise→fall half-cycle paths of the Z80N at 28 MHz), WHS +0.021 ns (M2M HyperRAM
`hr_rwds` input). No critical warnings; no block RAM demoted to LUTRAM; `t80n` `RegsH`/`RegsL` in
registers (expected). `check_timing`: 41 inputs / 85 outputs without I/O delays (all board I/O,
including SDRAM and SD), 2 unconstrained internal endpoints and 2 unclocked pins from
`nr_a2_pi_i2s_ctl_reg[6]` (Pi I²S clock select, unused on the MEGA65).

1. **[FIXED: Port A only samples and updates on the edges of CLK_28]** **SDRAM multicycle
   exceptions vs. `sdram_zxn` input registers** (`CORE/CORE.xdc:37-40`,
   `CORE/vhdl/sdram_zxn.vhd:241-245`). *Verified.*
   - The XDC copies MiSTer's `ZXNext.sdc` 2-cycle setup multicycle from the CPU clocks to
     `sdram_clk`.
   - But `sdram_zxn` registers `ram_a_addr/req/rd_n/di` on **every** 112 MHz edge and acts
     on the registered values one edge later. With the multicycle, the edge+1 capture is
     not timed, so `a_req_r` may see the new request while `a_addr_r` is still settling.
   - **Measured on the R6 build:** CPU → `a_req_r` datapath 12.49 ns (16 logic levels from
     `z80n/IR_reg` through the memory decode), CPU → `a_addr_r[13..20]` 10.0–11.9 ns (through the
     MMU). One 112 MHz cycle is 8.93 ns. The edge+1 capture therefore *does* see unsettled values
     in this placement, and `old_a_req = '0' and a_req_r = '1'` can start an access from a glitch,
     or with a half-settled address (a write to the wrong address corrupts RAM). The paths pass
     STA only because of the 2-cycle exception (slack 1.54 ns from `cpu_clk_div`, 4.74 ns from
     `cpu_clk_28`).
   - MiSTer's `sdram.sv` samples `old_req` on every edge too, so this is inherited, but the
     exception must be re-derived for this controller (guide 3.B.5, l.2583).
   - The reverse direction (`ram_a_wait`/`ram_a_do` → CPU, `-start -setup 2`) assumes the
     result is launched no later than edge +2: the worst `ram_a_wait` path is 10.75 ns, so
     simply sampling the inputs one edge later would break that side. Either drop the CPU→`sdram_clk` multicycle and close
     timing at 8.9 ns, or delay the request edge detection until the window the exception
     allows. The GHDL testbench cannot catch this (no timing).
   - **Fix:**
     - Launch edges, from the routed R6 design: CPU rise at 112 MHz edge 0 is valid at edge 2;
       CPU fall at edge 2 is valid at edge 4; `main_clk`/`main_clk_n` are valid one edge after
       launch. So the inputs are stable on every *even* edge, i.e. each edge of CLK_28.
     - The CPU captures wait/data on both edges of its clock, 2 cycles after launch. So the
       outputs may only change on even edges. Before the fix, a completed miss changed
       `ram_a_wait` on any edge, and the wait→Z80 paths are up to 10.75 ns long.
     - `sdram_zxn` now takes the CLK_28 phase from `clk_28_i` (a toggle sampled at 112 MHz). It
       evaluates Port A only on even edges, straight from the inputs, and updates
       `ram_a_wait_o`/`ram_a_do_o` only on even edges. The hit data no longer waits for the
       cache compare.
     - New XDC multicycle: `main_clk`/`main_clk_n` → the Port A registers, 2 cycles.
     - The testbench now models the ZX Next timing. It drives garbage for up to 2 cycles after
       each launch (a request glitch plus a phantom write), launches on random CLK_28 edges, uses
       the real one-cycle request pulse, sees the outputs 2 cycles late, and asserts that they
       only change on CLK_28 edges.
       - Old controller: 1780 data mismatches and 14763 odd-edge output changes.
       - New controller: passes.
     - R6 build of the fix: WNS +0.366 ns, WHS +0.053 ns. No critical warnings; check_timing and
       methodology are unchanged from the baseline. Not tested on hardware.
2. **Register-driven CPU clock** (`zxnext_top_m65.vhd:215-252`, `CORE.xdc:26-32`).
   - `CLK_i0` is a fabric flip-flop feeding a `BUFGMUX_CTRL`. The generated-clock constraints
     make it analyzable. The guide (3.B.3, l.2509) still calls a clock-enable rewrite
     "mandatory before any timing work".
   - This is acceptable for a first hardware test, but it is the first suspect if the CPU
     misbehaves only at some speeds.
3. **SDRAM I/O has no input/output delays.** IOB packing makes the timing deterministic, but run
   `check_timing` and confirm there are no unconstrained-I/O warnings (guide 4.2.4, l.4208).
4. **[FIXED: `mega65.vhd` now fails elaboration on R3]** **R3 builds a core that cannot work.**
   - `top_mega65-r3.vhd` is stock, so on R3 the core's SD and SDRAM inputs take their port
     defaults (no card, RAM reads 0).
   - `CORE.xdc:45-46` matches nothing on R3 (critical warnings; guide 4.2.2, l.4160).
   - Nothing checks `G_BOARD`, yet `CORE-R3.xpr` is maintained and the commit message lists R3.
     The help text already says R4–R6 only.
   - **Fix:** drop `CORE-R3.xpr`, or add an `assert G_BOARD /= "MEGA65_R3" severity failure`.
5. **[FIXED: lines reflowed to at most 43 characters]** **Help and welcome text is wider than the frame.** *Verified.*
   - The OSM is 720/16 = 45 columns and the frame takes 2, so at most 43 characters fit.
   - Too-long lines: `config.vhd:86` (44), `:87` (44), `:98` (45), `:106` (46), `:109` (44).

### B. Correctness

6. **[FIXED: now 3, all coefficients match `sys_top.v`]** **Audio filter coefficient `audio_cx1 = 2`** (`globals.vhd:166`). *Verified.* The core's
   `sys/sys_top.v:342` has `acx1 = 3`. This is the known template typo (guide S84, l.1552).
   One-line fix.
7. **Audio level / DC blocker** (`zxn_dc_blocker.vhd:39-46`).
   - The output is `audio & "000"`, about −6 dB relative to MiSTer's `{aud,4'b0}`.
   - The DC estimate starts at 0 and is never reset, so expect a thump at power-on. Minor.
8. **Reset during SD writes.** Resets drive the core directly (`main.vhd:202`). That is fine
   without vdrives (S60, l.1442). But the ZX Next writes its own SD card, and nothing holds a
   reset off while `sd_active` is high, so a reset mid-write can corrupt the card's FAT.
   Consider delaying the reset until SPI is idle.
9. **CONF_STR features dropped without a record** (guide S6/S14, l.1055/1106):
   - tape loading;
   - Kempston mouse;
   - stereo mix;
   - the scandoubler effects, aspect, crop and scale options;
   - the CPU-speed menu entry (`cpu_speed_sw_i => '0'`, `mega65.vhd:418`; F13 works).

   List them in the README as "not (yet) supported".

### C. Documentation and release hygiene

10. **Framework edits and a `MEGA65_Core` entity extension are undocumented.** The guide says
    the entity is fixed (1.2.1, l.364; App. B, l.4473). Here, `top_mega65-r4/r5/r6.vhd` were
    patched and `mega65.vhd:224-255` adds SD and SDRAM ports. This is justified (M2M V2.0.1
    has no SDRAM support and the core must own the SD cards), but it must be written down.
11. **`doc/m2m/exceptions.md` is still the template** (S35, l.1272). It should list:
    - the M2M top-file edits;
    - the entity extension;
    - `t80n.vhd`, `zxnext_top_m65.vhd` and `bram_xilinx.vhd` as replacements of upstream files;
    - `sdram_zxn.vhd` as a translation of `sdram.sv`;
    - the submodule SHA `7daebd1`.
12. **Identity files still on the template** (S29/S125, l.1222/1940; release page §1):
    - `README.md` (M2M's README);
    - `AUTHORS` (placeholder text);
    - `VERSIONS.md` (M2M's changelog);
    - `CORE/m2m-rom/m2m-rom.asm` header ("YOUR-PROJECT-NAME…");
    - the welcome screen's "Powered by MiSTer2MEGA65 Version [WIP] … 2022" (`config.vhd:83`).
13. **No fork of the MiSTer core** (S31–S33, l.1232–1259). The submodule points at MiSTer-devel
    directly, and changed files are replaced from `CORE/vhdl/zxnext/` instead. That works, but
    it has to be documented (see 11).
14. **Project-file drift.** `rtc.sv` has `SFType="SVerilog"` in R3–R5 but not in R6. R6 alone
    marks `vdrives.vhd` and `i2s_master.vhd` `AutoDisabled`. Otherwise the file lists match.
15. **`bram_xilinx.vhd` silently ignores `mem_init_file`** (l.33). No caller passes one today.
    Add an `assert mem_init_file = " " severity failure` (guide 3.A.6, l.2278).
16. **File headers missing credit lines.** `keyboard.vhd`, `clk.vhd`, `sdram_zxn.vhd` and
    `zxn_dc_blocker.vhd` lack the "based on ZXNext_MISTer / Powered by MiSTer2MEGA65" lines
    (`doc/m2m/example-file-headers.md`).

Passes
------

- **Clocks:** exact 28.000000 MHz, legal MMCM (VCO 700 MHz, fractional divider only on
  CLKOUT0), BUFG on every output, `xpm_cdc_async_rst` from `not locked`, generated clocks named
  on MMCM pins.
- **Vivado projects:** all four `.xpr` file lists in sync apart from the expected deltas;
  `FlattenHierarchy` and the `synth_pre.tcl` hook are set.
- **Video:** syncs and blanks active-high after inversion; `video_ce` = 14 MHz; `video_ce_ovl`
  correct for both scandoubler states; `VGA_DX/DY` 720×576; RGB bit-replicated.
- **VGA / ascal:** scandoubler, retro 15 kHz, CSync and ascal settings wired from the menu.
- **Audio:** signed 16-bit with saturation.
- **OSM menu:**
  - `OPTM_SIZE` 31 = 31 items = 31 groups;
  - every `C_MENU_*` index matches its line;
  - groups numbered monotonically, a single `OPTM_G_START`, submenus balanced;
  - `OPTM_DX/DY` correct (the main menu uses all 13 lines).
- **Welcome and help screens:** WHS structure correct.
- **Settings:** `SAVE_SETTINGS = false` is justified because QNICE has no SD card.
- **Unused features correctly "off":** no vdrives or CRT/ROMs (values correct); no QNICE
  devices (`x"EEEE"`); HyperRAM unused.
- **Tie-offs:** cartridge, IEC and joystick outputs idle; `cart_en_o = '1'`.
- **LEDs:** power LED blue during reset; drive LED shows SD activity.
- **Inputs:** full 80-key keyboard mapping, documented in the header and on the help page;
  joysticks with flip; RTC through MiSTer `rtc.sv`.
- **CDC:** OSM bits used in the correct domain; card detect synchronized; all core clocks from
  one MMCM.

Suggested order
---------------

1. Before hardware bring-up: 3 (1, 4, 5 and 6 are fixed).
2. Bring-up on R6, with the CPU at all four speeds and Layer 2 320×256/640×256 (exercises
   SDRAM Port B).
3. Then: 4, 8, and the documentation items 10–16.
