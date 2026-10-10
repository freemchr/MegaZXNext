@AGENTS.md

## Claude Code

Use the shared project guide above (`AGENTS.md`) as the source of truth for this repo.

Things that most often trip up work here:

- This is a **core**, not the M2M framework. `M2M/` is read-only except the three patched board
  tops (R4/R5/R6) that route SD and SDRAM to the core (AGENTS.md §4).
- The core owns **both SD slots**; the QNICE Shell has no SD card (AGENTS.md §3.3).
- Run the GHDL testbench (`cd CORE/sim && make`) after any change to `sdram_zxn.vhd`.
- The port has not been tested on hardware yet. Don't describe behavior as verified unless it was.
