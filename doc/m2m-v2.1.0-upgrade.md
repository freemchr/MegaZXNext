Upgrading M2M from V2.0.1 to V2.1.0
===================================

Analysis date: 2026-10-11, against upstream `develop` at `e7c7ace`. V2.1.0 is not
released yet (its `VERSIONS.md` entry still says "MONTH DAY, YEAR"). Either wait for the
release tag or pin to a specific `develop` commit. Don't track a moving branch.

Follow the wiki page
[Updating M2M in an existing core](https://github.com/sy2002/MiSTer2MEGA65/wiki/Updating-M2M-in-an-existing-core).
This document lists what is specific to MegaZXNext.

Starting point
--------------

* `M2M/` is byte-identical to upstream `V2.0.1:M2M` (tree `2a2aec3`), except for
  `M2M/vhdl/top_mega65-r4.vhd`, `-r5.vhd` and `-r6.vhd`. In each of those:
  1. The SDRAM tie-offs are removed, a DQ tri-state generate is added, and all `sdram_*` pins
     go to the CORE.
  2. Both SD slots are disconnected from the framework (`open` / `'1'`) and routed to the
     CORE's `sd_*` / `sd2_*` ports.
  3. A comment changes ("54 MHz" → "28 MHz").
* QNICE submodule: `2eb27dd` (the V2.0.1 pin). `develop` pins `2541cce` (V1.61, FAT32 fixes).
* The repo history is not connected to upstream.

What V2.1.0 changes, and what that means here
---------------------------------------------

**Drop-in** (unchanged locally, copy verbatim):

* `M2M/rom/{menu,options,shell,vdrives}.asm`, new `M2M/rom/menu_test.asm`. These add the
  OSM size checks (fatal error instead of a corrupted menu) and fix the Shell hang with two or
  more vdrives.
* `M2M/vhdl/av_pipeline/{analog_pipeline,av_pipeline,digital_pipeline,video_modes_pkg}.vhd`,
  new `vga_sync_reshaper.vhd`
* `M2M/vhdl/{framework,vdrives,debouncer,top_mega65-r3}.vhd`, new `M2M/vhdl/tests/*`
* `M2M/MEGA65-R3..R6.xdc`: restores the HyperRAM pblock (`SLICE_X0Y200:SLICE_X7Y224`)
* `CORE/m2m-rom/m2m-rom.asm` (comment only), `make_release.py`
* QNICE submodule → `2541cce`

**Needs CORE-side edits** (V2.1.0 does not compile without them):

| File | Edit |
| --- | --- |
| `CORE/vhdl/globals.vhd` | Add `VGA_STD_SYNC` and `HDMI_VIEW` (`framework.vhd` reads them with no fallback). Use the stock bypass values `C_VGA_SYNC_RESHAPER_OFF` and `C_HDMI_VIEW_LEGACY`. `video_modes_pkg` is already `use`d. |
| `CORE/vhdl/mega65.vhd` | Add port `qnice_hdmi_view_size_o : out std_logic_vector(1 downto 0)` and drive it `(others => '0')`. The new board tops connect it. |
| `CORE/CORE-R{3,4,5,6}.xpr` | Add `../M2M/vhdl/av_pipeline/vga_sync_reshaper.vhd` (VHDL 2008, synthesis + simulation) to all four. |
| `CORE/release.toml` | New, and only needed if you adopt `make_release.py`. Set the display name, file base and boards (R4/R5/R6). Match the `CORENAME` regex to `"MEGAZXNEXT V..."`. Set the shell config filename to `zxncfg`. |

**Manual 3-way merge** (local changes overlap with upstream changes):

* `M2M/vhdl/top_mega65-r4/r5/r6.vhd`: upstream adds the `qnice_hdmi_view_size` signal and
  two port-map lines. A trial `git merge-file` merged cleanly for all three. Keep every
  local SD/SDRAM edit.
* `CORE/vhdl/config.vhd`: one trivial conflict at `OPTM_DX`/`OPTM_DY`. Keep 25/13 and take
  the upstream comment.
* `CORE/vhdl/mega65.vhd`: if you merge against the template, there are two conflicts. Keep
  the local VGA/menu assignments and add the `qnice_hdmi_view_size_o` line. Keep the local
  device section (no vdrives). Ignore the template's `img_mounted_toggle_o` hunk.

Steps
-----

1. Make a backup branch and an `m2m-v2.1.0` branch. Add the upstream remote and fetch it.
2. Connect the histories: `git merge -s ours --allow-unrelated-histories <V2.0.1 commit>`.
   This is valid because `M2M/` equals V2.0.1.
3. Merge the chosen V2.1.0 commit with `--no-ff --no-commit`, or copy the drop-in files
   listed above by hand.
4. Resolve the three-way merges and make the CORE-side edits from the tables above.
5. Update the QNICE submodule and rebuild the toolchain and `m2m-rom.rom`.
6. Synthesize R4, R5 and R6. Compare WNS with the V2.0.1 build: the restored HyperRAM pblock
   changes placement next to the SDRAM controller and the 112 MHz logic.
7. On hardware, check the OSM (both submenus, help pages), HDMI and VGA modes, and that SD and
   SDRAM still work.
8. Update `AGENTS.md` §1/§4 and `doc/m2m/exceptions.md` with the new M2M version.

Risks
-----

* **Main menu is at its size limit.** It uses all 13 lines of `OPTM_DY`. With V2.1.0's checks,
  one more main-menu line without raising `OPTM_DY` is a fatal Shell error at boot.
* **Upstream SDRAM support** (a V2.1.0 backlog item modelled on C64MEGA65 `6a33db8`, not in
  `develop` yet). When it lands, it will collide head-on with the local board-top SDRAM patch
  and with `sdram_zxn.vhd`. At that point, decide whether to keep the local controller (it is
  tuned for the ZX Next's Layer 2 timing) or move to the framework's interface.
* **Placement/timing** shift from the HyperRAM pblock (step 6).
