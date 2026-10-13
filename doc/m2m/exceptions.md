How to update MegaZXNext
========================

The following changes have been made to MiSTer, MiSTer2MEGA65 and QNICE.
As soon as you update one of these modules, make sure you are applying the
changes described here.

MiSTer core ZXNext_MiSTer
-------------------------

The submodule `CORE/ZXNext_MiSTer` points to
https://github.com/MiSTer-devel/ZXNext_MISTer (commit `7daebd1`, 2026-09-28) and
is **not modified**. There is no fork. Instead, five upstream files are left out
of the Vivado projects and replaced by files in `CORE/vhdl/`:

| Upstream file (not in the `.xpr`) | Replacement                          |
| --------------------------------- | ------------------------------------ |
| `rtl/mister/zxnext_top.vhd`       | `CORE/vhdl/zxnext/zxnext_top_m65.vhd` |
| `rtl/mister/bram.vhd`             | `CORE/vhdl/zxnext/bram_xilinx.vhd`    |
| `rtl/cpu/t80n.vhd`                | `CORE/vhdl/zxnext/t80n.vhd`           |
| `rtl/mister/sdram.sv`             | `CORE/vhdl/sdram_zxn.vhd`             |
| `sys/sd_card.sv`                  | `CORE/vhdl/sd_card_zxn.vhd`           |

All other ZX Next RTL is compiled from the submodule into the VHDL library
`zxnext`. The `.xpr` files list every file explicitly.

When you update the submodule:

1. `git -C CORE/ZXNext_MiSTer diff 7daebd1 <new> -- <file>` for each of the five
   upstream files above, and carry the changes over to the replacement.
2. Look for files that upstream added, removed or renamed in `rtl/`, and update
   the file lists of **all four** `CORE/CORE-R*.xpr` (library `zxnext`).
3. Update the commit in this file and in `AGENTS.md` §1.

### `rtl/mister/zxnext_top.vhd` → `zxnext_top_m65.vhd`

The MEGA65 top level of the ZX Next (entity `zxnext_top_m65`). Changes:

* No PS/2 keyboard: the membrane matrix (8 rows x 7 columns) is driven directly
  by `CORE/vhdl/keyboard.vhd`.
* No PS/2 mouse: the mouse inputs are idle.
* CPU clock: a `BUFGMUX_CTRL` switches between the register driven clock
  `CLK_i0` (3.5/7/14 MHz) and `CLK_28` instead of MiSTer's fabric clock mux.
  `CORE/CORE.xdc` names `CLK_i0_reg` and `i_bufgmux_cpu`: keep these names.
* CPU speed changes: the BUFGMUX select follows `zxn_cpu_speed` directly, and
  `CLK_i0` does not rise for 15 `CLK_28` cycles after a speed change, so the
  memory cycle that straddles the switch gets its full time (MiSTer's mux can
  lose that opcode fetch). Test: `cd CORE/sim && make speed`.
* `CLK_28_n` is the MMCM's 180 degree output instead of an inverter.

### `rtl/mister/bram.vhd` → `bram_xilinx.vhd`

Same entities (`dpram`, `mlab`) and ports, written as inferable VHDL instead of
Altera `altsyncram`/`altdpram`. `mem_init_file` (`.mif`) is not supported; no
caller uses it today.

### `rtl/cpu/t80n.vhd` → `zxnext/t80n.vhd`

A copy with one fix: in the block I/O parity calculation,
`(ioq and x"7")` masks a 9-bit vector with a 4-bit literal. Quartus accepts this,
Vivado does not. The mask is now `"000000111"`. Re-apply this to a new upstream
version (search for `MegaZXNext:`).

### `rtl/mister/sdram.sv` → `sdram_zxn.vhd`

A VHDL translation, reworked for the MEGA65 SDRAM at 112 MHz. See the file
header. It is not a drop-in translation any more: changes to `sdram.sv` have to
be re-implemented by hand, then checked with `cd CORE/sim && make`.

### `sys/sd_card.sv` → `sd_card_zxn.vhd`

A line-by-line VHDL translation of MiSTer's virtual SPI SD card, fixed to SDHC,
an 8-bit buffer interface (WIDE=0) and one clock. The buffer is `zxnext.dpram`.
One addition: `idle_o`, used by `sd_image.vhd` for a CPU wait that closes a
race of the original (see the `sd_image.vhd` header). Port upstream changes by
hand, then run `cd CORE/sim && make sd`.

MiSTer2MEGA65
-------------

Framework version: V2.0.1. Only the three board top files are changed:
`M2M/vhdl/top_mega65-r4.vhd`, `top_mega65-r5.vhd` and `top_mega65-r6.vhd`
(R3 is stock and not supported). In each one:

1. **SDRAM:** remove the SDRAM tie-offs, add a generate with the DQ tri-state
   buffers (`sdram_dq_out`/`sdram_dq_oe_n`/`sdram_dq_in`), and connect all
   `sdram_*` pins to the CORE.
2. **SD cards:** the framework's SD outputs (`sd_reset_o`, `sd_clk_o`,
   `sd_mosi_o`, `sd2_*`) go to the CORE's `fw_sd_*_i`/`fw_sd2_*_i` ports, and
   the CORE drives the pins (`sd_*_o`/`sd2_*_o`): it passes the framework's
   signals through, except for the slot that holds the ZX Next's SD card image
   once the Shell has mounted it. MISO and card detect go from the pins to the
   framework, MISO also to the CORE.
3. A comment: "54 MHz" → "28 MHz".

For this, `MEGA65_Core` (`CORE/vhdl/mega65.vhd`) has additional `sdram_*`,
`sd_*`, `sd2_*` and `fw_sd*` ports that the stock M2M entity does not have.

When you update M2M, re-apply 1 and 2 to the new board tops (a three-way merge
of the old stock file, the new stock file and our file works).
`doc/m2m-v2.1.0-upgrade.md` describes the update to V2.1.0.

QNICE
-----

No changes to QNICE or to `M2M/rom`. The core specific Shell code is in
`CORE/m2m-rom/m2m-rom.asm`: `PREP_START` mounts the ZX Next's SD card image
(`ZXN_MOUNT`), and the heap is 64 words smaller than in the template to make
room for its variables.
