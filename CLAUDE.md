@AGENTS.md

## Claude Code

Use the shared project guide above (`AGENTS.md`) as the source of truth for this repo.

Things that most often trip up work here:

- This is a **core**, not the M2M framework. `M2M/` is read-only except the three patched board
  tops (R3-R6) that route SDRAM (R4-R6) and the SD slots to the core (AGENTS.md §4).
- The ZX Next's SD card is an **image file** on the MEGA65 card; after startup the core drives the
  card and QNICE must not touch it (AGENTS.md §3.3).
- Run the GHDL testbenches (`cd CORE/sim && make`) after any change to `zxnext_top_m65.vhd` (CPU
  clock), `sdram_zxn.vhd`, `sd_image.vhd` or `sd_card_zxn.vhd`.
- Only partly tested on hardware (R6: NextZXOS, 48K BASIC and the Browser work). Don't describe
  behavior as verified unless it was run on a MEGA65.

## M2M porting lessons

Lessons learnt from earlier MiSTer2MEGA65 ports (memory timing, M2M framework bugs, Vivado and QNICE
pitfalls, MEGA65 hardware, verification, releases): read
`/home/freemchr/github/m2m-porting-lessons/README.md`
(https://github.com/freemchr/m2m-porting-lessons) before porting work or when debugging framework,
Vivado or hardware problems. The rules of this repo take precedence.
